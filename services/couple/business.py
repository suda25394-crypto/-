"""Authorization, optimistic versions and validated model output for one couple."""

from __future__ import annotations

import hashlib
import json
import secrets
from threading import RLock
from dataclasses import dataclass

from .database import encode
from .profile_schema import public_projection, validate_profile


class Failure(Exception):
    def __init__(self, status, code, message):
        self.status, self.code, self.message = status, code, message
        super().__init__(code)


def invalid():
    raise Failure(422, "invalid_data", "内容不符合要求，请检查后重试。")


def missing():
    # Private and nonexistent IDs share the same response.
    raise Failure(404, "not_found", "找不到这条可访问的记录。")


def check_version(actual, expected):
    if actual != expected:
        raise Failure(409, "version_conflict", "内容已更新。请刷新并核对最新版本。")


def text_value(value, limit):
    if not isinstance(value, str) or not value.strip() or len(value.strip()) > limit:
        invalid()
    return value.strip()


MODULES = frozenset(("date", "wish", "memory", "calendar"))


def clean_items(items):
    if not isinstance(items, list) or len(items) > 8:
        invalid()
    result = []
    for item in items:
        if (
            not isinstance(item, dict)
            or set(item) != {"module", "title", "body"}
            or not isinstance(item["module"], str)
            or item["module"] not in MODULES
        ):
            invalid()
        result.append(
            {
                "module": item["module"],
                "title": text_value(item["title"], 120),
                "body": text_value(item["body"], 2500),
            }
        )
    return result


def clean_completion(value):
    try:
        if not isinstance(value, dict):
            invalid()
        items = clean_items(value.get("items", []))
        memories = value.get("memories", [])
        if not isinstance(memories, list) or len(memories) > 4:
            invalid()
        return {
            "reply": text_value(value.get("reply"), 6000),
            "items": items,
            "memories": [text_value(m, 300) for m in memories],
        }
    except (Failure, TypeError):
        raise Failure(
            502, "model_format", "模型返回的结构不完整，未写入模块。"
        ) from None


@dataclass(frozen=True)
class Actor:
    id: str
    name: str
    pair: str
    upstream: str
    session: str


def bump_epoch(c, actor):
    c.execute("UPDATE couples SET epoch=epoch+1 WHERE id=?", (actor.pair,))


def read_epoch(c, actor):
    return c.execute("SELECT epoch FROM couples WHERE id=?", (actor.pair,)).fetchone()[
        0
    ]


class Records:
    def __init__(self, db):
        self.db = db
        self.release_lock = RLock()

    def profiles(self, c, a, for_model=False):
        result = []
        rows = c.execute(
            "SELECT p.*,u.name FROM profiles p JOIN users u ON u.id=p.owner AND u.pair=p.pair WHERE p.pair=?",
            (a.pair,),
        )
        for row in rows:
            published = json.loads(row["released"]) if row["released"] else None
            mine = row["owner"] == a.id and not for_model
            if not mine and published is None:
                continue
            data = json.loads(row["draft"]) if mine else published
            profile = {
                "id": row["owner"],
                "owner": row["owner"],
                "name": row["name"],
                "version": row["version"],
                "published": published is not None,
                "data": data,
            }
            if mine:
                profile["published_data"] = published
            result.append(profile)
        return result

    def memories(self, c, a, for_model=None):
        clauses, args = ["pair=?"], [a.pair]
        if for_model == "shared":
            clauses.append("scope='shared'")
        elif for_model == "private":
            clauses.append("(scope='shared' OR (scope='private' AND owner=?))")
            args.append(a.id)
        else:
            clauses.append("(scope='shared' OR owner=?)")
            args.append(a.id)
        return [
            dict(r)
            for r in c.execute(
                "SELECT id,owner,scope,text,version FROM memories WHERE "
                + " AND ".join(clauses)
                + " ORDER BY rowid",
                args,
            )
        ]

    def modules(self, c, a):
        return [
            dict(r) | {"scope": "shared"}
            for r in c.execute(
                "SELECT id,owner,module,title,body,version FROM modules WHERE pair=? ORDER BY rowid DESC",
                (a.pair,),
            )
        ]

    def drafts(self, c, a):
        rows = c.execute(
            """SELECT id,owner,version,scope,status,items FROM drafts WHERE pair=? AND source NOT LIKE 'manual:%' AND (scope='shared' OR owner=?) ORDER BY rowid DESC""",
            (a.pair, a.id),
        )
        return [dict(r) | {"items": json.loads(r["items"])} for r in rows]

    def context(self, c, a, scope):
        profiles = [
            {"owner": v["owner"], "data": v["data"]} for v in self.profiles(c, a, True)
        ]
        memories = [
            {"owner": v["owner"], "text": v["text"]} for v in self.memories(c, a, scope)
        ]
        # Revocable profile or memory contents can be echoed in an old AI reply.
        # No old AI replies, pending drafts or private conversation history cross contexts.
        recent = c.execute(
            """SELECT input,owner FROM chats
            WHERE pair=? AND scope=? AND (scope='shared' OR owner=?) AND done=1
            AND epoch=(SELECT epoch FROM couples WHERE id=chats.pair)
            ORDER BY at DESC,rowid DESC LIMIT 3""",
            (a.pair, scope, a.id),
        ).fetchall()
        prior = [
            {"role": "user", "owner": r["owner"], "text": r["input"]}
            for r in reversed(recent)
        ]
        feedback = c.execute(
            """SELECT module,action FROM feedback WHERE pair=?
            AND (scope='shared' OR (?='private' AND owner=?)) ORDER BY id DESC LIMIT 10""",
            (a.pair, scope, a.id),
        ).fetchall()
        return {
            "profiles": profiles,
            "memories": memories,
            "modules": self.modules(c, a)[:8],
            "conversation": prior,
            "feedback": [dict(row) for row in reversed(feedback)],
        }

    def profile_write(self, a, version, data=None, publish=False, action="save"):
        with self.release_lock, self.db.connection(True) as c:
            row = c.execute(
                "SELECT * FROM profiles WHERE pair=? AND owner=?", (a.pair, a.id)
            ).fetchone()
            check_version(row["version"] if row else 0, version)
            if action == "save":
                try:
                    normalized = validate_profile(data)
                    projection = public_projection(normalized) if publish else None
                except (ValueError, TypeError):
                    invalid()
                released = (
                    encode(projection) if publish else row["released"] if row else None
                )
                c.execute(
                    """INSERT INTO profiles(pair,owner,version,draft,released) VALUES(?,?,?,?,?)
                    ON CONFLICT(pair,owner) DO UPDATE SET version=excluded.version,draft=excluded.draft,released=excluded.released""",
                    (a.pair, a.id, version + 1, encode(normalized), released),
                )
            elif action == "withdraw":
                if not row:
                    missing()
                c.execute(
                    "UPDATE profiles SET version=version+1,released=NULL WHERE pair=? AND owner=?",
                    (a.pair, a.id),
                )
            else:
                if not row:
                    missing()
                # Keep a version tombstone so a delayed offline update cannot recreate deleted content.
                c.execute(
                    "UPDATE profiles SET version=version+1,released=NULL,draft='{}' WHERE pair=? AND owner=?",
                    (a.pair, a.id),
                )
            bump_epoch(c, a)

    def memory_write(self, a, key, version, value=None, scope=None):
        with self.release_lock, self.db.connection(True) as c:
            row = c.execute(
                "SELECT version FROM memories WHERE pair=? AND id=? AND owner=?",
                (a.pair, key, a.id),
            ).fetchone()
            if not row:
                missing()
            check_version(row["version"], version)
            if value is None:
                c.execute("DELETE FROM memories WHERE pair=? AND id=?", (a.pair, key))
            else:
                if scope not in ("private", "shared"):
                    invalid()
                c.execute(
                    "UPDATE memories SET version=version+1,scope=?,text=? WHERE pair=? AND id=?",
                    (scope, text_value(value, 300), a.pair, key),
                )
            bump_epoch(c, a)

    def manual_module(self, a, req, kind, title, body):
        item = clean_items([{"module": kind, "title": title, "body": body}])[0]
        key = hashlib.sha256(encode(["manual", a.pair, a.id, req]).encode()).hexdigest()
        with self.release_lock, self.db.connection(True) as c:
            prior = c.execute(
                "SELECT items FROM drafts WHERE id=? AND pair=?", (key, a.pair)
            ).fetchone()
            if prior:
                if json.loads(prior["items"]) != [item]:
                    raise Failure(
                        409, "request_mismatch", "同一提交编号已用于其他内容。"
                    )
                return
            c.execute(
                "INSERT INTO drafts VALUES(?,?,?,?,?,?,?,?)",
                (
                    key,
                    a.pair,
                    a.id,
                    "shared",
                    "confirmed",
                    1,
                    encode([item]),
                    "manual:" + req,
                ),
            )
            c.execute(
                "INSERT INTO modules VALUES(?,?,?,?,?,?,?,?,?)",
                (
                    secrets.token_hex(12),
                    a.pair,
                    a.id,
                    kind,
                    item["title"],
                    item["body"],
                    1,
                    key,
                    0,
                ),
            )
            bump_epoch(c, a)

    def module_write(self, a, key, version, title, body):
        with self.release_lock, self.db.connection(True) as c:
            row = c.execute(
                "SELECT version FROM modules WHERE pair=? AND id=?", (a.pair, key)
            ).fetchone()
            if not row:
                missing()
            check_version(row["version"], version)
            c.execute(
                "UPDATE modules SET version=version+1,title=?,body=? WHERE pair=? AND id=?",
                (text_value(title, 120), text_value(body, 2500), a.pair, key),
            )
            bump_epoch(c, a)

    def resolve_draft(self, a, key, version, items, action):
        with self.release_lock, self.db.connection(True) as c:
            row = c.execute(
                """SELECT * FROM drafts WHERE pair=? AND id=? AND (scope='shared' OR owner=?)""",
                (a.pair, key, a.id),
            ).fetchone()
            if not row:
                missing()
            next_state = "confirmed" if action == "confirm" else "cancelled"
            current = json.loads(row["items"])
            chosen = clean_items(items) if items is not None else current
            if row["status"] == next_state and (
                action == "cancel" or chosen == current
            ):
                return  # response lost after commit, same operation
            if row["status"] != "pending":
                raise Failure(409, "draft_closed", "这份草稿已处理，请刷新。")
            check_version(row["version"], version)
            if action == "confirm":
                if not chosen:
                    invalid()
                for i, item in enumerate(chosen):
                    c.execute(
                        "INSERT INTO modules VALUES(?,?,?,?,?,?,?,?,?)",
                        (
                            secrets.token_hex(12),
                            a.pair,
                            a.id,
                            item["module"],
                            item["title"],
                            item["body"],
                            1,
                            key,
                            i,
                        ),
                    )
                bump_epoch(c, a)
            # Only categories survive; feedback does not retain private message text.
            for kind in {item["module"] for item in current + chosen}:
                old = [item for item in current if item["module"] == kind]
                new = [item for item in chosen if item["module"] == kind]
                feedback = (
                    "cancelled"
                    if action == "cancel" or not new
                    else "edited"
                    if old != new
                    else "confirmed"
                )
                c.execute(
                    "INSERT INTO feedback(pair,owner,scope,draft,module,action) VALUES(?,?,?,?,?,?)",
                    (a.pair, a.id, row["scope"], key, kind, feedback),
                )
            c.execute(
                "UPDATE drafts SET version=version+1,items=?,status=? WHERE pair=? AND id=?",
                (encode(chosen), next_state, a.pair, key),
            )

    def materialize(self, c, a, req, scope, result):
        if result["items"]:
            c.execute(
                "INSERT INTO drafts VALUES(?,?,?,?,?,?,?,?)",
                (
                    secrets.token_hex(12),
                    a.pair,
                    a.id,
                    scope,
                    "pending",
                    1,
                    encode(result["items"]),
                    req,
                ),
            )
        if scope == "private":
            for m in result["memories"]:
                c.execute(
                    "INSERT INTO memories VALUES(?,?,?,?,?,?,?)",
                    (secrets.token_hex(12), a.pair, a.id, "candidate", m, 1, req),
                )
