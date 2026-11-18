"""Stepwise delivery. SQLite is never write-locked while awaiting model I/O."""

import hashlib
import json
import re
import secrets
import time
from datetime import datetime, timezone, timedelta

from .business import (
    Failure,
    missing,
    check_version,
    check_target_items,
    clean_completion,
    read_epoch,
)
from .dp_recall import index_turn
from . import profile_mode, intent
from .database import encode
from .upstream import UpstreamError

BEIJING = timezone(timedelta(hours=8))
MENTION = re.compile(r"(?<![A-Za-z0-9_@])@(?:AI|DP)(?![A-Za-z0-9_])", re.IGNORECASE)


class Conversations:
    def __init__(self, db, records, upstream):
        self.db, self.records, self.upstream = db, records, upstream

    @staticmethod
    def private_history(c, a, module_id=None, scope="private"):
        result = []
        rows = c.execute(
            """SELECT request_id,input,output,done,at,owner FROM chats WHERE pair=? AND (owner=? OR scope='shared') AND scope=? AND module_id IS ? ORDER BY at,rowid""",
            (a.pair, a.id, scope, module_id),
        )
        for r in rows:
            common = {
                "owner": r["owner"],
                "created_at": r["at"],
                "request_id": r["request_id"],
            }
            result.append(
                common | {"id": r["request_id"], "role": "user", "text": r["input"]}
            )
            if r["output"] and r["done"]:
                result.append(
                    common
                    | {
                        "id": r["request_id"] + "-ai",
                        "role": "assistant",
                        "text": json.loads(r["output"])["reply"],
                    }
                )
        return result

    def receipt(self, a, req):
        key = hashlib.sha256(encode((a.pair, a.id, req)).encode()).hexdigest()
        with self.db.connection() as c:
            info = c.execute(
                """SELECT u.outcome,u.in_tokens,u.out_tokens,r.at,r.reported_model
                     FROM usage u LEFT JOIN model_receipts r ON r.usage_id=u.id WHERE pair=? AND request_id=?
                     ORDER BY u.id DESC LIMIT 1""",
                (a.pair, key),
            ).fetchone()
        return {
            "called": bool(info),
            "mode": self.db.settings.mode,
            "requested_model": "deepseek-flash" if info else None,
            **(dict(info) if info else {}),
        }

    def send(self, a, req, scope, text, module_id=None, module_version=None):
        key = (a.pair, a.id, req)
        condition = "pair=? AND owner=? AND request_id=?"
        # These IDs contain no application data and are distinct across both actors.
        remote_id = hashlib.sha256(encode(key).encode()).hexdigest()
        now = int(time.time())
        lease = secrets.token_hex(12)
        with self.records.release_lock, self.db.connection(True) as c:
            inserted = c.execute(
                "INSERT OR IGNORE INTO chats(pair,owner,request_id,scope,input,at,module_id,module_version) VALUES(?,?,?,?,?,?,?,?)",
                (*key, scope, text, now, module_id, module_version),
            )
            row = c.execute("SELECT * FROM chats WHERE " + condition, key).fetchone()
            if (
                row["scope"],
                row["input"],
                row["module_id"],
                row["module_version"],
            ) != (scope, text, module_id, module_version):
                raise Failure(409, "request_mismatch", "同一提交编号已用于其他内容。")
            if row["done"]:
                return
            task = row["intent"] or intent.route(text, module_id)
            if (
                task == "general"
                and not intent.knowledge_request(text)
                and profile_mode.personal_statement(text)
            ):
                task = "personal"
            if inserted.rowcount:
                implicit = (
                    intent.select_plan(c, a, text, req)
                    if task == "product"
                    and not module_id
                    and (scope == "private" or MENTION.search(text))
                    else None
                )
                c.execute(
                    "UPDATE chats SET intent=?,bound_id=?,bound_version=? WHERE "
                    + condition,
                    (
                        task,
                        implicit["id"] if implicit else None,
                        implicit["version"] if implicit else None,
                        *key,
                    ),
                )
                row = c.execute(
                    "SELECT * FROM chats WHERE " + condition, key
                ).fetchone()
            target_key = module_id or row["bound_id"]
            expected = module_version if module_id else row["bound_version"]
            target = None
            if target_key:
                if task == "product":
                    target = self.records.module(c, a, target_key)
                    check_version(target["version"], expected)
                else:
                    header = c.execute(
                        "SELECT version FROM modules WHERE id=? AND pair=?",
                        (target_key, a.pair),
                    ).fetchone()
                    if not header:
                        missing()
                    check_version(header["version"], expected)
            if row["busy_until"] > now:
                raise Failure(409, "in_progress", "正在处理这条消息，稍后刷新。")
            if row["uncertain"] and not row["output"]:
                raise Failure(
                    409,
                    "model_outcome_unknown",
                    "上次模型调用结果不明。此次重试不会再次扣用量；如仍需回复，请主动发起新请求。",
                )
            if inserted.rowcount:
                profile_mode.attach_turn(c, a, row)
            if (
                inserted.rowcount
                and not module_id
                and scope == "private"
                and profile_mode.handle_private(c, a, row)
            ):
                return
            c.execute(
                "UPDATE chats SET busy_until=?,lease=? WHERE " + condition,
                (now + 240, lease, *key),
            )

        def change(c, set_sql, *args):
            updated = c.execute(
                "UPDATE chats SET " + set_sql + " WHERE " + condition + " AND lease=?",
                (*args, *key, lease),
            )
            if updated.rowcount != 1:
                raise Failure(409, "lease_changed", "另一会话正在恢复，请刷新。")

        try:
            if scope == "shared" and not module_id and not row["posted"]:
                self.upstream.channel_post(
                    a.upstream, text, remote_id + "-user", "user"
                )
                with self.db.connection(True) as c:
                    change(c, "posted=1")
            if scope == "shared" and not module_id and not MENTION.search(text):
                with self.db.connection(True) as c:
                    change(c, "done=1,epoch=?", read_epoch(c, a))
                    index_turn(c, *key, text)
                return
            result = json.loads(row["output"]) if row["output"] else None
            generation_epoch = row["epoch"]
            if result is None:
                with self.db.connection(True) as c:
                    generation_epoch = read_epoch(c, a)
                    if target:
                        check_version(
                            self.records.module(c, a, target_key)["version"],
                            expected,
                        )
                    context = (
                        self.records.context(c, a, scope, text, target)
                        if task == "product"
                        else intent.conversational_context(c, a, scope, module_id, task)
                    )
                    context["intent"] = [task]
                    ambiguous = (
                        task == "product"
                        and not target
                        and intent.EDIT.search(text)
                        and intent.PLAN.search(text)
                    )
                    if ambiguous:
                        context["intent"] = ["choose_plan"]
                    guided = None
                    if task not in (
                        "safety",
                        "relationship",
                    ) and not intent.knowledge_request(text):
                        guided = profile_mode.mode_context(c, a, row, generation_epoch)
                    if guided:
                        context["profile_mode"] = [guided]
                    day = datetime.now(BEIJING).date().isoformat()
                    count = c.execute(
                        "SELECT count(*) FROM usage WHERE pair=? AND day=? AND outcome!='rejected'",
                        (a.pair, day),
                    ).fetchone()[0]
                    if count >= self.db.settings.daily:
                        raise Failure(
                            429, "daily_limit", "今天的模型调用额度已用完，明天再试。"
                        )
                    usage_id = c.execute(
                        "INSERT INTO usage(pair,day,request_id,outcome) VALUES(?,?,?,'reserved')",
                        (a.pair, day, remote_id),
                    ).lastrowid
                    change(c, "uncertain=1,epoch=?", generation_epoch)
                try:
                    raw = self.upstream.complete(a.upstream, scope, text, context)
                except UpstreamError as e:
                    # Do not repeat a potentially billed timeout or unknown delivery.
                    unknown = e.status == 504 or e.code in (
                        "model_outcome_unknown",
                        "upstream_timeout",
                        "gateway_timeout",
                        "model_format",
                        "content_filter",
                    )
                    safe_rejection = e.status in (
                        400,
                        401,
                        403,
                        413,
                        422,
                        429,
                    ) or e.code in (
                        "model_disabled",
                        "model_offline",
                        "gateway_disabled",
                        "upstream_disabled",
                    )
                    if e.code == "content_filter":
                        safe_rejection = False
                    with self.db.connection(True) as c:
                        c.execute(
                            "UPDATE usage SET outcome=? WHERE id=?",
                            ("rejected" if safe_rejection else "uncertain", usage_id),
                        )
                        change(c, "uncertain=?", int(unknown))
                    raise
                with self.db.connection(True) as c:
                    reported = (
                        raw.get("reported_model") if isinstance(raw, dict) else None
                    )
                    c.execute(
                        "INSERT OR IGNORE INTO model_receipts VALUES(?,?,?)",
                        (
                            usage_id,
                            int(time.time()),
                            reported[:100] if isinstance(reported, str) else None,
                        ),
                    )
                    usage = raw.get("usage") if isinstance(raw, dict) else {}
                    usage = usage if isinstance(usage, dict) else {}

                    def tokens(key):
                        n = usage.get(key)
                        return n if type(n) is int and 0 <= n <= 10000000 else None

                    c.execute(
                        "UPDATE usage SET outcome='returned',in_tokens=?,out_tokens=? WHERE id=?",
                        (
                            tokens("prompt_tokens"),
                            tokens("completion_tokens"),
                            usage_id,
                        ),
                    )
                if isinstance(raw, dict) and (task != "product" or ambiguous):
                    raw = raw | {"items": []}
                    if task != "personal":
                        raw = raw | {"memories": []}
                result = clean_completion(raw)
                if module_id:
                    result["memories"] = []
                if (
                    scope == "private"
                    and not module_id
                    and task not in ("general", "relationship", "safety")
                ):
                    profile_mode.prepare_reply(text, result)
                if target:
                    check_target_items(target, result["items"])
                with self.db.connection(True) as c:
                    if read_epoch(c, a) != generation_epoch:
                        change(c, "uncertain=0")
                    else:
                        change(c, "output=?,uncertain=0", encode(result))

            # Serialize release with consent changes without holding a SQLite transaction across I/O.
            # Muse's run configuration uses one worker for this two-user service.
            with self.records.release_lock:
                # Revalidate user access and consent immediately before releasing a model response.
                self.upstream.check_member(a.upstream, a.id)
                with self.db.connection(True) as c:
                    active = c.execute(
                        "SELECT 1 FROM sessions WHERE digest=? AND pair=? AND expires>?",
                        (a.session, a.pair, int(time.time())),
                    ).fetchone()
                    if not active:
                        raise Failure(401, "unauthorized", "登录已结束，请重新登录。")
                    stale = read_epoch(c, a) != generation_epoch
                    if stale:
                        change(c, "output=NULL,uncertain=0")
                if stale:
                    raise Failure(
                        409,
                        "context_changed",
                        "授权资料刚刚变化。请重试以使用最新资料。",
                    )
                if scope == "shared" and not module_id:
                    self.upstream.channel_post(
                        a.upstream, result["reply"], remote_id + "-ai", "assistant"
                    )
                with self.db.connection(True) as c:
                    change(c, "done=1")
                    self.records.materialize(c, a, req, scope, result, target)
                    if not module_id and scope == "private":
                        profile_mode.after_reply(c, a, row, result)
                    index_turn(c, *key, text)
        finally:
            with self.db.connection(True) as c:
                c.execute(
                    "UPDATE chats SET busy_until=0,lease=NULL WHERE "
                    + condition
                    + " AND lease=?",
                    (*key, lease),
                )
