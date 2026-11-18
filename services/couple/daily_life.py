"""Shared plan revisions, independent read receipts and the wish → plan → memory trail."""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
import re
import secrets
import struct
import time
import zlib
from datetime import date, datetime, timezone, timedelta
from typing import Annotated, Literal

from fastapi import Depends, Request
from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from .business import Actor, Failure, bump_epoch, check_version, invalid, missing
from .database import encode

SQL_SCHEMA = """
CREATE TABLE IF NOT EXISTS life_plans (
 plan TEXT PRIMARY KEY REFERENCES modules ON DELETE CASCADE,
 wish TEXT UNIQUE REFERENCES modules, memory TEXT UNIQUE REFERENCES modules,
 stage TEXT NOT NULL CHECK(stage IN ('planned','wish','remembered')),
 day TEXT NOT NULL DEFAULT '', clock TEXT NOT NULL DEFAULT '',
 place TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '',
 consent_floor INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS life_events (
 id INTEGER PRIMARY KEY, module_id TEXT NOT NULL REFERENCES modules ON DELETE CASCADE,
 actor TEXT NOT NULL, action TEXT NOT NULL, fields TEXT NOT NULL,
 version INTEGER NOT NULL, at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS life_events_module ON life_events(module_id,id);
CREATE TABLE IF NOT EXISTS life_event_prior (event INTEGER PRIMARY KEY REFERENCES life_events ON DELETE CASCADE, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS life_seen (
 event INTEGER NOT NULL REFERENCES life_events ON DELETE CASCADE, owner TEXT NOT NULL,
 PRIMARY KEY(event,owner)
);
CREATE TABLE IF NOT EXISTS life_operations (
 pair TEXT NOT NULL REFERENCES couples, owner TEXT NOT NULL, request_id TEXT NOT NULL,
 fingerprint TEXT NOT NULL, result TEXT NOT NULL, PRIMARY KEY(pair,owner,request_id)
);
CREATE TABLE IF NOT EXISTS life_photos (
 memory TEXT PRIMARY KEY REFERENCES modules ON DELETE CASCADE, owner TEXT NOT NULL, png BLOB NOT NULL
);
"""
BEIJING = timezone(timedelta(hours=8))
MAX_PNG = 384 * 1024
Req = Annotated[str, StringConstraints(pattern=r"^[a-zA-Z0-9_-]{8,96}$")]


class Operation(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    version: int = Field(ge=1, le=2147483647)
    request_id: Req


class Meeting(Operation):
    day: str = Field(min_length=10, max_length=10)
    clock: str = Field(default="", max_length=5)
    place: str = Field(default="", max_length=160)
    address: str = Field(default="", max_length=240)


class Recollection(Operation):
    occurred: Literal[True]
    note: str = Field(default="", max_length=1500)
    photo: str = Field(default="", max_length=524288)


def today():
    return datetime.now(BEIJING).date().isoformat()


def event(c, a, key, version, action, fields=(), prior=None):
    # Only the latest joint meeting edit can expose previous structured details.
    c.execute(
        "DELETE FROM life_event_prior WHERE event IN (SELECT id FROM life_events WHERE module_id=?)",
        (key,),
    )
    change = c.execute(
        "INSERT INTO life_events(module_id,actor,action,fields,version,at) VALUES(?,?,?,?,?,?)",
        (key, a.id, action, encode(list(fields)), version, int(time.time())),
    )
    if prior:
        c.execute(
            "INSERT INTO life_event_prior VALUES(?,?)",
            (change.lastrowid, encode(prior)),
        )


_MEET = r"(?:集合|见面|会合|碰面)"
_CHANGE = r"(?:改[为到成]|调整[为到]|推迟[到至]|提前[到至]|移[到至]|定[在为]|安排在)"
_PERIOD = r"(?:凌晨|早上|早晨|上午|中午|下午|傍晚|晚上)"
_NUM = r"(?:\d{1,2}|[零〇一二两三四五六七八九十]{1,3})"
_TIME = rf"(?:{_PERIOD}\s*)?(?:{_NUM}\s*(?:[:：]\s*\d{{2}}|[点时](?:整|半|{_NUM}分?)?))|{_PERIOD}|待定|待确认|待补充"
_CLOCK_TEXT = rf"(?P<time>{_TIME})"
_PLAN = r"(?:(?:把|将)?(?:我们|双方)?(?:已?确认好的?|原定的?|共同的?)?(?:本次|这次|周末|当天)?(?:计划|约会|行程|日程))"
_MARKED = re.compile(
    rf"(?:(?:{_PLAN}(?:的)?)|把|将)?{_MEET}(?:时间)?\s*(?:[:：]|{_CHANGE}|是|为|在)?\s*{_CLOCK_TEXT}(?:\s*{_MEET})?"
)
_RESCHEDULE = re.compile(rf"{_PLAN}\s*{_CHANGE}\s*{_CLOCK_TEXT}(?:\s*{_MEET})?")
_TIME_FIRST = re.compile(
    rf"(?:周末|当天)?\s*{_CLOCK_TEXT}\s*(?:在[^，,；;。\n]{{1,20}})?{_MEET}"
)
_TIME_ONLY = re.compile(rf"(?:{_CHANGE}\s*)?{_CLOCK_TEXT}")
_OUTING_START = re.compile(
    rf"(?:周末|当天|这次)?\s*{_CHANGE}\s*{_CLOCK_TEXT}\s*一起(?:出发(?:去.{{1,35}})?|去[^，,；;。\n]{{1,35}})"
)
_SPLIT = re.compile(r"[\n。；;，,]+")


def _numeral(word):
    if word.isdecimal():
        return int(word)
    digits = "零一二三四五六七八九"
    word = word.replace("两", "二").replace("〇", "零")
    if word.count("十") == 1:
        tens, ones = word.split("十")
        if len(tens) <= 1 and len(ones) <= 1:
            return (digits.index(tens) if tens else 1) * 10 + (
                digits.index(ones) if ones else 0
            )
    if len(word) == 1 and word in digits:
        return digits.index(word)
    if len(word) == 2 and word[0] == "零" and word[1] in digits:
        return digits.index(word[1])
    return -1


def _parse_clock(value):
    # The empty clock is a supported state on existing handsets ("时间待补充").
    if re.fullmatch(rf"{_PERIOD}|待定|待确认|待补充", value):
        return ""
    match = re.fullmatch(
        rf"(?P<period>{_PERIOD})?\s*(?P<hour>{_NUM})\s*(?:[:：]\s*(?P<min>\d{{2}})|[点时](?P<chinese>整|半|{_NUM}分?)?)",
        value,
    )
    if not match:
        raise Failure(422, "meeting_clock", "请使用 24 小时制或把集合时间标为待定。")
    period, hour, minute, chinese = match.groups()
    h = _numeral(hour)
    m = 0
    if minute:
        m = int(minute)
    elif chinese == "半":
        m = 30
    elif chinese and chinese != "整":
        m = _numeral(chinese.rstrip("分"))
    if not (0 <= h < 24 and 0 <= m < 60):
        raise Failure(
            422,
            "meeting_clock",
            "请在草稿中使用明确的 24 小时制集合时间，例如「集合时间：16:00」。",
        )
    if not period:
        if h < 13 and not (minute is not None and len(hour) == 2 and hour.isdecimal()):
            return ""
    elif period in ("下午", "晚上", "傍晚") and 1 <= h < 12:
        h += 12
    elif period == "中午" and 1 <= h <= 2:
        h += 12
    elif not (
        period in ("早上", "早晨", "上午", "凌晨")
        and h < 12
        or period == "中午"
        and h in (11, 12)
        or period == "下午"
        and h == 12
    ):
        raise Failure(
            422, "meeting_clock", "请把集合时间写成 24 小时制，避免混淆上午和下午。"
        )
    return f"{h:02}:{m:02}"


def _confirmed_clock(old_body, body, request):
    def clauses(text):
        return [part.strip() for part in _SPLIT.split(text) if part.strip()]

    def explicit(part):
        return (
            _MARKED.fullmatch(part)
            or _RESCHEDULE.fullmatch(part)
            or _TIME_FIRST.fullmatch(part)
        )

    def schedule_request(part):
        part = re.sub(r"^(?:@(?:DP|AI)\s+|请|帮我|帮我们)+", "", part, flags=re.I)
        return explicit(part) or _TIME_ONLY.fullmatch(part) and re.match(_CHANGE, part)

    prior = set(clauses(old_body))
    # A bare time in an edited draft can only mean the meeting time when the original request did.
    allow_short = any(schedule_request(x) for x in clauses(request))
    clock_mentions = []
    changed = False
    for part in clauses(body):
        match = explicit(part) or (allow_short and _TIME_ONLY.fullmatch(part))
        if (
            not match
            and allow_short
            and not re.search(r"看电影|开场|散场|演出|吃饭|用餐|排队|结束", part)
        ):
            match = _OUTING_START.fullmatch(part)
        if match:
            clock_mentions.append(match["time"])
            changed |= part not in prior
        elif part not in prior and re.match(
            rf"^(?:把|将)?{_MEET}时间\s*(?:[:：]|{_CHANGE})", part
        ):
            raise Failure(
                422,
                "meeting_clock",
                "请单独写一行「集合时间：16:00」或「集合时间：待定」，再确认草稿。",
            )
    if not changed:
        return None
    times = {_parse_clock(value) for value in clock_mentions}
    if len(times) != 1:
        raise Failure(
            422,
            "meeting_clock",
            "草稿含多个集合时间。请保留一个时间，或写「集合时间：待定」。",
        )
    return times.pop()


def content_edit(c, a, before, title, body, *, confirmed_request=None):
    fields = [k for k, v in (("title", title), ("body", body)) if v != before[k]]
    prior = None
    if (
        confirmed_request is not None
        and "body" in fields
        and before["module"] in ("date", "calendar")
    ):
        key = before["id"]
        plan = c.execute(
            "SELECT stage,clock FROM life_plans WHERE plan=?", (key,)
        ).fetchone()
        if not plan or plan["stage"] == "planned":
            clock = _confirmed_clock(before["body"], body, confirmed_request)
            old_clock = plan["clock"] if plan else ""
            if clock is not None and clock != old_clock:
                c.execute(
                    """INSERT INTO life_plans(plan,stage,clock) VALUES(?,'planned',?)
                ON CONFLICT(plan) DO UPDATE SET clock=excluded.clock""",
                    (key, clock),
                )
                fields.append("clock")
                prior = {"clock": old_clock} if old_clock and clock else None
    if fields:
        event(
            c,
            a,
            before["id"],
            before["version"] + 1,
            "meeting" if "clock" in fields else "edit",
            fields,
            prior,
        )


def _photo(value):
    """Accept bounded, metadata-free RGB(A) thumbnails produced by the handset."""
    try:
        raw = base64.b64decode(value, validate=True)
        if len(raw) > MAX_PNG or not raw.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError
        pos, header, ended, compressed = 8, None, False, bytearray()
        while pos + 12 <= len(raw):
            size, tag = struct.unpack_from(">I4s", raw, pos)
            end = pos + 8 + size
            block = raw[pos + 8 : end]
            if (
                end + 4 > len(raw)
                or zlib.crc32(tag + block) != struct.unpack_from(">I", raw, end)[0]
            ):
                raise ValueError
            if tag == b"IHDR" and pos == 8 and size == 13:
                w, h, bits, color, comp, filt, interlace = struct.unpack(
                    ">IIBBBBB", block
                )
                if not (
                    1 <= w <= 512
                    and 1 <= h <= 512
                    and bits == 8
                    and color in (2, 6)
                    and comp == filt == interlace == 0
                ):
                    raise ValueError
                header = (w, h, 3 if color == 2 else 4)
            elif tag == b"IDAT" and header:
                compressed.extend(block)
            elif tag == b"IEND" and not size and end + 4 == len(raw):
                ended = True
                break
            elif tag not in (b"sRGB", b"gAMA", b"cHRM", b"sBIT", b"pHYs") or not header:
                raise ValueError
            pos = end + 4
        if not (header and ended and compressed):
            raise ValueError
        width, height, channels = header
        stride = width * channels + 1
        decoder = zlib.decompressobj()
        pixels = decoder.decompress(bytes(compressed), stride * height + 1)
        if (
            len(pixels) != stride * height
            or not decoder.eof
            or decoder.unused_data
            or any(pixels[i] > 4 for i in range(0, len(pixels), stride))
        ):
            raise ValueError

        # Strip all optional chunks; dimensions, colour and IDAT are sufficient to display.
        def chunk(tag, data):
            return (
                struct.pack(">I", len(data))
                + tag
                + data
                + struct.pack(">I", zlib.crc32(tag + data))
            )

        return raw[:33] + chunk(b"IDAT", bytes(compressed)) + chunk(b"IEND", b"")
    except (ValueError, binascii.Error, struct.error, zlib.error):
        raise Failure(422, "invalid_photo", "请选择可读取的图片后再试。") from None


def _meeting(form):
    try:
        if date.fromisoformat(form.day).isoformat() != form.day:
            raise ValueError
    except ValueError:
        invalid()
    if form.clock and not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", form.clock):
        invalid()
    place, address = form.place.strip(), form.address.strip()
    if address and (
        not place
        or len(address) < 6
        or any(x in address for x in ("待补", "待定", "不清楚", "不知道"))
    ):
        raise Failure(
            422, "unclear_address", "请填城市及完整地名或门牌；不确定时可留空。"
        )
    return {"day": form.day, "clock": form.clock, "place": place, "address": address}


def _new_record(c, a, kind, title, body):
    draft, key = secrets.token_hex(12), secrets.token_hex(12)
    items = [dict(module=kind, title=title, body=body)]
    c.execute(
        "INSERT INTO drafts VALUES(?,?,?,?,?,?,?,?)",
        (
            draft,
            a.pair,
            a.id,
            "shared",
            "confirmed",
            1,
            encode(items),
            "manual:life:" + key,
        ),
    )
    c.execute(
        "INSERT INTO modules VALUES(?,?,?,?,?,?,?,?,?)",
        (key, a.pair, a.id, kind, title, body, 1, draft, 0),
    )
    return key


def _relationship(c, key):
    return c.execute(
        "SELECT * FROM life_plans WHERE plan=? OR wish=? OR memory=?", (key, key, key)
    ).fetchone()


def _touch(c, key):
    return c.execute(
        "UPDATE modules SET version=version+1 WHERE id=? RETURNING version", (key,)
    ).fetchone()[0]


def _remember(c, a, record, plan, form):
    if record["module"] not in ("date", "calendar") or (
        plan and plan["stage"] == "wish"
    ):
        raise Failure(409, "not_planned", "请先把心愿排进计划。")
    if plan and plan["memory"]:
        raise Failure(409, "already_remembered", "这次出行已有回忆，刷新后即可打开。")
    note = form.note.strip()
    if not note and not form.photo:
        raise Failure(422, "empty_memory", "请留下一句话或选择一张照片。")
    photo = _photo(form.photo) if form.photo else None
    key = _new_record(c, a, "memory", record["title"], note or "共同出行照片")
    if photo:
        c.execute("INSERT INTO life_photos VALUES(?,?,?)", (key, a.id, photo))
    pid = record["id"]
    c.execute(
        """INSERT INTO life_plans(plan,memory,stage) VALUES(?,?,'remembered')
                 ON CONFLICT(plan) DO UPDATE SET memory=excluded.memory,stage='remembered'""",
        (pid, key),
    )
    at = int(time.time())
    c.execute(
        """INSERT INTO activity_steps VALUES(?,?,'happened',?,1)
                 ON CONFLICT(module_id,owner,step) DO UPDATE SET at=excluded.at,version=version+1
                 WHERE activity_steps.at IS NULL""",
        (pid, a.id, at),
    )
    event(c, a, pid, _touch(c, pid), "remembered")
    event(c, a, key, 1, "memory")
    return key


def _update_meeting(c, a, record, plan, form):
    values = _meeting(form)
    if record["module"] not in ("date", "calendar", "wish") or (
        plan and plan["stage"] == "remembered"
    ):
        raise Failure(409, "plan_closed", "这条记录不能再排进日程。")
    new_plan = record["module"] == "wish" and plan is None
    if new_plan:
        pid = _new_record(c, a, "calendar", record["title"], record["body"])
        c.execute(
            "INSERT INTO life_plans(plan,wish,stage) VALUES(?,?,'planned')",
            (pid, record["id"]),
        )
    elif plan:
        pid = plan["plan"]
    else:
        pid = record["id"]
        c.execute("INSERT INTO life_plans(plan,stage) VALUES(?,'planned')", (pid,))
    if record["module"] == "wish" and plan and plan["stage"] == "planned":
        raise Failure(409, "already_planned", "这条心愿已有计划，请从关联计划修改。")
    restored = bool(plan and plan["stage"] == "wish")
    changed = [
        key for key, value in values.items() if value != (plan[key] if plan else "")
    ]
    if not new_plan and not restored and not changed:
        return pid
    version = 1 if new_plan else _touch(c, pid)
    floor = (
        version if not plan or restored or "day" in changed else plan["consent_floor"]
    )
    c.execute(
        """UPDATE life_plans SET stage='planned',day=?,clock=?,place=?,address=?,consent_floor=?
                 WHERE plan=?""",
        (*values.values(), floor, pid),
    )
    prior = {
        k: plan[k] for k in changed if plan and plan[k] and values[k] and not restored
    }
    event(
        c,
        a,
        pid,
        version,
        "scheduled" if new_plan or restored else "meeting",
        changed,
        prior,
    )
    if record["module"] == "wish":
        event(c, a, record["id"], _touch(c, record["id"]), "to_plan")
    return pid


def _return(c, a, record, plan):
    if (
        not plan
        or record["id"] != plan["plan"]
        or not plan["wish"]
        or plan["stage"] != "planned"
    ):
        raise Failure(409, "cannot_return", "当前记录无法放回原心愿。")
    c.execute("UPDATE life_plans SET stage='wish' WHERE plan=?", (plan["plan"],))
    event(c, a, plan["plan"], _touch(c, plan["plan"]), "returned")
    event(c, a, plan["wish"], _touch(c, plan["wish"]), "wish_again")
    return plan["wish"]


def changes(c, a, before=None, limit=50):
    args = [a.id, a.pair, a.id]
    clause = ""
    if before is not None:
        clause = " AND e.id<?"
        args.append(before)
    rows = c.execute(
        """SELECT e.id,e.module_id,e.actor,e.action,e.fields,e.at,e.version,
           m.version AS current_version,m.title,m.body,u.name AS author,prev.data AS prior,
           (s.event IS NOT NULL) AS seen,p.day,p.clock,p.place,p.address FROM life_events e
           JOIN modules m ON m.id=e.module_id JOIN users u ON u.pair=m.pair AND u.id=e.actor
           LEFT JOIN life_plans p ON p.plan=m.id LEFT JOIN life_event_prior prev ON prev.event=e.id
           LEFT JOIN life_seen s ON s.event=e.id AND s.owner=?
           WHERE m.pair=? AND e.actor!=?"""
        + clause
        + " ORDER BY e.id DESC LIMIT ?",
        (*args, limit),
    )
    result = []
    for r in rows:
        current = r["version"] == r["current_version"]
        fields = json.loads(r["fields"])
        # Only current joint fields appear; stale revisions carry no previous user-authored content.
        values = {f: r[f] for f in fields if current and r[f]}
        result.append(
            {
                k: r[k]
                for k in (
                    "id",
                    "module_id",
                    "actor",
                    "author",
                    "action",
                    "at",
                    "title",
                    "version",
                    "current_version",
                )
            }
            | {
                "seen": bool(r["seen"]),
                "fields": fields,
                "current": values,
                "previous": json.loads(r["prior"]) if current and r["prior"] else {},
            }
        )
    return result


def state(c, a):
    plans = []
    outing = []
    day = today()
    for row in c.execute(
        """SELECT p.*,m.title,m.version FROM life_plans p
        JOIN modules m ON m.id=p.plan WHERE m.pair=? ORDER BY p.day,p.clock,m.rowid""",
        (a.pair,),
    ):
        item = dict(row)
        plans.append(item)
        if item["day"] != day or item["stage"] != "planned":
            continue
        votes = c.execute(
            """SELECT proposal_version FROM activity_votes WHERE module_id=? AND choice='accept'
                AND proposal_version BETWEEN ? AND ? GROUP BY proposal_version HAVING COUNT(*)=2
                ORDER BY proposal_version DESC LIMIT 1""",
            (row["plan"], row["consent_floor"], row["version"]),
        ).fetchone()
        declined = c.execute(
            "SELECT 1 FROM activity_votes WHERE module_id=? AND proposal_version=? AND choice='decline'",
            (row["plan"], row["version"]),
        ).fetchone()
        if votes and not declined:
            item_today = item | {
                "agreed_current": votes["proposal_version"] == row["version"]
            }
            outing.append(item_today)
    photos = [
        dict(r)
        for r in c.execute(
            """SELECT f.memory,f.owner FROM life_photos f
        JOIN modules m ON m.id=f.memory WHERE m.pair=?""",
            (a.pair,),
        )
    ]
    return {
        "journeys": plans,
        "today_plans": outing,
        "joint_changes": changes(c, a),
        "memory_photos": photos,
    }


def register(api, actor):
    A = Depends(actor)

    def mutate(s, a, key, action, form):
        data = form.model_dump()
        if data.get("photo"):
            data["photo"] = hashlib.sha256(data["photo"].encode()).hexdigest()
        signature = hashlib.sha256(encode([key, action, data]).encode()).hexdigest()
        with s.records.release_lock, s.db.connection(True) as c:
            record = s.records.module(c, a, key)
            req = (a.pair, a.id, form.request_id)
            done = c.execute(
                "SELECT * FROM life_operations WHERE pair=? AND owner=? AND request_id=?",
                req,
            ).fetchone()
            if done:
                if done["fingerprint"] != signature:
                    raise Failure(
                        409, "request_mismatch", "同一提交编号已用于其他操作。"
                    )
                return {"module_id": done["result"]}
            check_version(record["version"], form.version)
            plan = _relationship(c, key)
            if action == "meeting":
                target = _update_meeting(c, a, record, plan, form)
            elif action == "remember":
                target = _remember(c, a, record, plan, form)
            else:
                target = _return(c, a, record, plan)
            c.execute(
                "INSERT INTO life_operations VALUES(?,?,?,?,?)",
                (*req, signature, target),
            )
            bump_epoch(c, a, invalidate_history=False)
            return {"module_id": target}

    @api.post("/v1/modules/{key}/life/meeting")
    def meeting(key: str, form: Meeting, request: Request, a: Actor = A):
        return mutate(request.app.state, a, key, "meeting", form)

    @api.post("/v1/modules/{key}/life/remember")
    def remember(key: str, form: Recollection, request: Request, a: Actor = A):
        return mutate(request.app.state, a, key, "remember", form)

    @api.post("/v1/modules/{key}/life/return")
    def back(key: str, form: Operation, request: Request, a: Actor = A):
        return mutate(request.app.state, a, key, "return", form)

    @api.get("/v1/life/changes")
    def history(request: Request, before: int | None = None, a: Actor = A):
        with request.app.state.db.connection() as c:
            return {"changes": changes(c, a, before)}

    @api.put("/v1/life/changes/{event_id}/read")
    def read(event_id: int, request: Request, a: Actor = A):
        with request.app.state.db.connection(True) as c:
            row = c.execute(
                """SELECT 1 FROM life_events e JOIN modules m ON m.id=e.module_id
                 WHERE e.id=? AND m.pair=? AND e.actor!=?""",
                (event_id, a.pair, a.id),
            ).fetchone()
            if not row:
                missing()
            c.execute("INSERT OR IGNORE INTO life_seen VALUES(?,?)", (event_id, a.id))
        return {"ok": True}

    @api.get("/v1/modules/{key}/life/photo")
    def photo(key: str, request: Request, a: Actor = A):
        with request.app.state.db.connection() as c:
            request.app.state.records.module(c, a, key)
            row = c.execute(
                "SELECT png FROM life_photos WHERE memory=?", (key,)
            ).fetchone()
            if not row:
                missing()
            return {"png": base64.b64encode(row[0]).decode()}

    @api.delete("/v1/modules/{key}/life/photo")
    def remove_photo(key: str, request: Request, a: Actor = A):
        with (
            request.app.state.records.release_lock,
            request.app.state.db.connection(True) as c,
        ):
            request.app.state.records.module(c, a, key)
            row = c.execute(
                "SELECT owner FROM life_photos WHERE memory=?", (key,)
            ).fetchone()
            if row is None:
                return {"ok": True}
            if row["owner"] != a.id:
                missing()
            c.execute("DELETE FROM life_photos WHERE memory=?", (key,))
            event(c, a, key, _touch(c, key), "photo_removed")
            bump_epoch(c, a)
        return {"ok": True}
