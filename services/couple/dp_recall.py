"""Scoped, incremental lexical recall. Only live, authorized rows can supply evidence."""

import re
import time
from datetime import datetime, timezone, timedelta


SQL_SCHEMA = """
CREATE TABLE IF NOT EXISTS dp_targets(draft TEXT PRIMARY KEY REFERENCES drafts, module_id TEXT NOT NULL REFERENCES modules, expected INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS dp_evidence(memory TEXT PRIMARY KEY REFERENCES memories ON DELETE CASCADE,
 at INTEGER, quote TEXT, origin TEXT NOT NULL, category TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS dp_history_floor(pair TEXT PRIMARY KEY REFERENCES couples, epoch INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS dp_current_budget(pair TEXT NOT NULL,owner TEXT NOT NULL,domain TEXT NOT NULL,
 memory TEXT NOT NULL,PRIMARY KEY(pair,owner,domain));
CREATE TABLE IF NOT EXISTS dp_terms(word TEXT NOT NULL, memory TEXT NOT NULL REFERENCES memories ON DELETE CASCADE, PRIMARY KEY(word,memory));
CREATE TABLE IF NOT EXISTS dp_turn_terms(word TEXT NOT NULL,pair TEXT NOT NULL,owner TEXT NOT NULL,request_id TEXT NOT NULL,
 PRIMARY KEY(word,pair,owner,request_id));
"""
GROUPS = {
    "budget": ("预算", "花销", "花费", "费用", "开销", "价位", "价格", "多少钱"),
    "outing": (
        "周末",
        "周六",
        "周日",
        "约会",
        "出门",
        "出去",
        "人多",
        "安静",
        "错峰",
        "看展",
        "散步",
    ),
    "food": ("晚饭", "晚餐", "吃饭", "美食", "餐厅"),
    "cinema": ("电影", "影片", "看片", "看什么"),
    "birthday": ("生日", "庆生"),
    "book": ("书摊", "书店", "书市"),
}
FOLLOW = re.compile("依据|为什么|原话|来源|根据什么|哪天说|怎么知道")


def words(text):
    t = text.lower()
    tags = {key for key, variants in GROUPS.items() if any(v in t for v in variants)}
    for run in re.findall(r"[\u3400-\u9fff]+|[a-z0-9]+", t):
        if run.isascii():
            tags.add(run)
        else:
            tags.update(run[i : i + 2] for i in range(len(run) - 1))
    return sorted(tags)[:512]


def index_turn(c, pair, owner, req, text):
    c.executemany(
        "INSERT OR IGNORE INTO dp_turn_terms VALUES(?,?,?,?)",
        ((w, pair, owner, req) for w in words(text)),
    )


def budget_domain(text):
    for domain, markers in (
        ("travel", ("旅行", "旅游")),
        ("groceries", ("买菜", "食材")),
        ("monthly", ("月度", "每月", "月预算")),
        ("gifts", ("礼物", "送礼")),
    ):
        if any(marker in text for marker in markers):
            return domain
    return "outing"


def remember(c, row, value, scope, *, migration=False):
    source = c.execute(
        "SELECT input,at FROM chats WHERE pair=? AND owner=? AND request_id=?",
        (row["pair"], row["owner"], row["source"]),
    ).fetchone()
    existing = c.execute(
        "SELECT * FROM dp_evidence WHERE memory=?", (row["id"],)
    ).fetchone()
    if existing and value == row["text"]:
        return
    # Legacy memory versions may contain an un-timestamped correction; never attribute it to the original utterance.
    from_chat = (
        source
        and value == row["text"]
        and (
            row["scope"] == "candidate"
            or (migration and row["version"] <= 2 and value in source["input"])
        )
    )
    stamp = source["at"] if from_chat else None if migration else int(time.time())
    quote = source["input"][:650] if from_chat else value
    origin = row["source"] if from_chat else "memory-edit:" + row["id"]
    terms = words(value)
    kind = (
        (
            "exception"
            if any(
                t in value for t in ("生日", "这次", "临时", "例外", "庆生", "这一次")
            )
            else "usual"
        )
        if "budget" in terms
        else "fact"
    )
    c.execute(
        "INSERT OR REPLACE INTO dp_evidence VALUES(?,?,?,?,?)",
        (row["id"], stamp, quote, origin, kind),
    )
    if kind == "usual":
        # Keep a pointer (no content) after deletion/withdrawal so an older budget cannot resurface.
        c.execute(
            """INSERT INTO dp_current_budget VALUES(?,?,?,?) ON CONFLICT(pair,owner,domain)
                  DO UPDATE SET memory=excluded.memory""",
            (row["pair"], row["owner"], budget_domain(value), row["id"]),
        )
    c.execute("DELETE FROM dp_terms WHERE memory=?", (row["id"],))
    c.executemany("INSERT INTO dp_terms VALUES(?,?)", ((w, row["id"]) for w in terms))


def backfill(c):
    # Pre-migration grants may have been withdrawn; carry forward the previous privacy boundary.
    c.execute("INSERT OR IGNORE INTO dp_history_floor SELECT id,epoch FROM couples")
    for row in c.execute(
        "SELECT * FROM memories WHERE scope IN ('shared','private') ORDER BY rowid"
    ):
        remember(c, row, row["text"], row["scope"], migration=True)
    for row in c.execute("SELECT pair,owner,request_id,input FROM chats WHERE done=1"):
        index_turn(c, *row)


def retrieve(c, a, scope, text, module_id=None):
    if FOLLOW.search(text):
        prev = c.execute(
            """SELECT input FROM chats WHERE pair=? AND (owner=? OR scope='shared') AND scope=?
          AND module_id IS ? AND done=1 AND epoch>=COALESCE((SELECT epoch FROM dp_history_floor WHERE pair=?),0) ORDER BY at DESC,rowid DESC LIMIT 4""",
            (a.pair, a.id, scope, module_id, a.pair),
        ).fetchall()
        text += " " + next((r[0] for r in prev if not FOLLOW.search(r[0])), "")
    terms = words(text)
    if not terms:
        return [], []
    params = ",".join("?" for _ in terms)
    rows = c.execute(
        f"""SELECT m.*,e.at,e.quote,e.origin,e.category,COUNT(*) hits FROM dp_terms t
      JOIN memories m ON m.id=t.memory JOIN dp_evidence e ON e.memory=m.id
      WHERE t.word IN ({params}) AND m.pair=? AND (m.scope='shared' OR (?='private' AND m.scope='private' AND m.owner=?))
      AND (e.category!='usual' OR EXISTS(SELECT 1 FROM dp_current_budget b WHERE b.pair=m.pair AND b.owner=m.owner AND b.memory=m.id))
      GROUP BY m.id ORDER BY hits DESC,e.at DESC,m.rowid DESC LIMIT 48""",
        (*terms, a.pair, scope, a.id),
    ).fetchall()
    use_exception = "birthday" in terms or any(
        s in text for s in ("临时", "例外", "那一次")
    )
    memories = []
    for r in rows:
        kind = r["category"]
        if kind == "exception" and not use_exception:
            continue
        if kind == "usual" and budget_domain(r["text"]) != budget_domain(text):
            continue
        private_source = scope == "private" and r["owner"] == a.id
        memories.append(
            dict(
                owner=r["owner"],
                scope=r["scope"],
                id=r["id"],
                text=r["text"],
                at=r["at"],
                source_time=(
                    datetime.fromtimestamp(
                        r["at"], timezone(timedelta(hours=8))
                    ).isoformat(timespec="minutes")
                    if r["at"] is not None
                    else None
                ),
                source=r["origin"] if private_source else "published:" + r["id"],
                quote=r["quote"] if private_source else r["text"],
                quote_type="source" if private_source else "published_memory",
                category=kind,
            )
        )
        if len(memories) >= 6:
            break
    # Source chats belonging to a memory are recalled through its revocable pointer only.
    history = c.execute(
        f"""SELECT ch.owner,ch.input AS text,ch.at,ch.request_id AS source,ch.module_id,COUNT(*) hits
        FROM dp_turn_terms t JOIN chats ch USING(pair,owner,request_id) WHERE t.word IN ({params})
        AND ch.pair=? AND ch.scope=? AND (ch.owner=? OR ch.scope='shared') AND (? IS NULL OR ch.module_id=?)
        AND ch.done=1 AND ch.epoch>=COALESCE((SELECT epoch FROM dp_history_floor WHERE pair=ch.pair),0)
        AND NOT EXISTS(SELECT 1 FROM memories m WHERE m.pair=ch.pair AND m.owner=ch.owner AND m.source=ch.request_id)
        GROUP BY ch.pair,ch.owner,ch.request_id HAVING COUNT(*)>=2 ORDER BY hits DESC,ch.at DESC LIMIT 4""",
        (*terms, a.pair, scope, a.id, module_id, module_id),
    ).fetchall()
    return memories, [
        dict(
            owner=r["owner"],
            text=r["text"][:380],
            at=r["at"],
            source=r["source"],
            module_id=r["module_id"],
        )
        for r in history
    ]
