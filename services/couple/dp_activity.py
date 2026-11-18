"""Per-activity decisions and first-person experience evidence for the private demo."""

from __future__ import annotations

import re
import time
from typing import Literal

from fastapi import Depends, Request
from pydantic import BaseModel, ConfigDict, Field

from .business import Actor, Failure, bump_epoch, check_version, missing, text_value

from .dp_recall import words

SQL_SCHEMA = """
CREATE TABLE IF NOT EXISTS activity_votes (
    module_id TEXT NOT NULL REFERENCES modules(id), proposal_version INTEGER NOT NULL,
    owner TEXT NOT NULL, choice TEXT NOT NULL CHECK(choice IN ('accept','decline','pending')),
    note TEXT NOT NULL, version INTEGER NOT NULL, PRIMARY KEY(module_id,proposal_version,owner)
);
CREATE TABLE IF NOT EXISTS activity_steps (
    module_id TEXT NOT NULL REFERENCES modules(id), owner TEXT NOT NULL,
    step TEXT NOT NULL CHECK(step IN ('saved','planned','happened')),
    at INTEGER, version INTEGER NOT NULL, PRIMARY KEY(module_id,owner,step)
);
CREATE TABLE IF NOT EXISTS activity_reviews (
    module_id TEXT NOT NULL REFERENCES modules(id), owner TEXT NOT NULL,
    text TEXT, scope TEXT NOT NULL CHECK(scope IN ('private','shared')),
    version INTEGER NOT NULL, at INTEGER NOT NULL, PRIMARY KEY(module_id,owner)
);
"""


class Update(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    version: int = Field(ge=0, le=2147483647)
    proposal_version: int = Field(ge=1, le=2147483647)


class Vote(Update):
    choice: Literal["accept", "decline", "pending"]
    note: str = Field(default="", max_length=300)


class Step(Update):
    enabled: bool


class Review(Update):
    text: str = Field(min_length=1, max_length=600)
    scope: Literal["private", "shared"]


def activity(c, a, key, version):
    record = c.execute(
        "SELECT version FROM modules WHERE id=? AND pair=?", (key, a.pair)
    ).fetchone()
    if record is None:
        missing()
    check_version(record["version"], version)


def state(c, a):
    pair = c.execute("SELECT a,b FROM couples WHERE id=?", (a.pair,)).fetchone()
    names = dict(c.execute("SELECT id,name FROM users WHERE pair=?", (a.pair,)))
    items = {}
    for r in c.execute(
        "SELECT id,version FROM modules WHERE pair=? ORDER BY rowid DESC", (a.pair,)
    ):
        items[r["id"]] = {
            "module_id": r["id"],
            "proposal_version": r["version"],
            "agreed": False,
            "votes": [
                {
                    "owner": uid,
                    "name": names.get(uid, "伴侣"),
                    "choice": None,
                    "note": "",
                    "version": 0,
                }
                for uid in pair
            ],
            "steps": {},
            "reviews": [],
            "my_review_version": 0,
        }
    for row in c.execute(
        """SELECT v.* FROM activity_votes v JOIN modules m ON m.id=v.module_id
           AND m.version=v.proposal_version WHERE m.pair=?""",
        (a.pair,),
    ):
        item = items[row["module_id"]]
        for vote in item["votes"]:
            if vote["owner"] == row["owner"]:
                vote.update(
                    choice=row["choice"], note=row["note"], version=row["version"]
                )
        item["agreed"] = all(v["choice"] == "accept" for v in item["votes"])
    for row in c.execute(
        """SELECT s.* FROM activity_steps s JOIN modules m ON m.id=s.module_id
           WHERE m.pair=? AND s.owner=?""",
        (a.pair, a.id),
    ):
        items[row["module_id"]]["steps"][row["step"]] = {
            "at": row["at"],
            "version": row["version"],
        }
    for row in c.execute(
        """SELECT f.* FROM activity_reviews f JOIN modules m ON m.id=f.module_id
           WHERE m.pair=? AND (f.owner=? OR (f.scope='shared' AND f.text IS NOT NULL))""",
        (a.pair, a.id),
    ):
        item = items[row["module_id"]]
        if row["owner"] == a.id:
            item["my_review_version"] = row["version"]
        if row["text"] is not None:
            item["reviews"].append(
                dict(row) | {"name": names.get(row["owner"], "伴侣")}
            )
    return {"activities": list(items.values())}


def context(c, a, scope, text):
    """Return relevant individual evidence only inside its current grant."""
    terms = set(words(text))
    general = any(
        w in text
        for w in (
            "约会",
            "周末",
            "出去",
            "出门",
            "去哪",
            "去哪里",
            "推荐活动",
            "推荐地点",
            "活动建议",
            "我们做什么",
        )
    )
    interest = any(
        w in text
        for w in (
            "建议",
            "推荐",
            "下次",
            "安排",
            "计划",
            "提议",
            "再去",
            "我们要",
            "我们想",
        )
    )
    general = general or bool(
        re.fullmatch(
            r"(?:@(?:AI|DP)\s*)?(?:下次|再|请|给我|帮我|请帮我)*(?:推荐|安排|推荐一下|推荐一次|给些建议)[？?！!。]?",
            text.strip(),
            re.I,
        )
    )
    decisions = {}
    experiences = []

    def score(row, content):
        matches = len(
            terms.intersection(words(row["title"] + " " + row["body"] + " " + content))
        )
        return matches + int(general and row["module"] in ("date", "wish", "calendar"))

    for r in c.execute(
        """SELECT v.module_id,v.owner,v.choice,v.note,m.module,m.title,m.body
           FROM activity_votes v JOIN modules m ON m.id=v.module_id AND m.version=v.proposal_version
           WHERE m.pair=? ORDER BY v.rowid DESC""",
        (a.pair,),
    ):
        group = decisions.setdefault(
            r["module_id"],
            {
                "rank": 0,
                "evidence": {
                    "module_id": r["module_id"],
                    "title": r["title"],
                    "votes": [],
                },
            },
        )
        group["rank"] = max(group["rank"], score(r, r["note"]))
        group["evidence"]["votes"].append(
            {k: r[k] for k in ("owner", "choice", "note")}
        )
    for r in c.execute(
        """SELECT f.*,m.title,m.body,m.module FROM activity_reviews f JOIN modules m ON m.id=f.module_id
           WHERE m.pair=? AND f.text IS NOT NULL AND (f.scope='shared' OR (?='private' AND f.owner=?))
           ORDER BY f.at DESC,f.rowid DESC""",
        (a.pair, scope, a.id),
    ):
        rank = score(r, r["text"])
        if rank or (
            interest and any(w in text for w in ("体验", "上次", "实际", "反馈"))
        ):
            experiences.append(
                (
                    rank,
                    {
                        k: r[k]
                        for k in ("module_id", "title", "owner", "text", "scope", "at")
                    },
                )
            )
    selected = []
    for entry in sorted(decisions.values(), key=lambda v: -v["rank"]):
        if not entry["rank"] or len(selected) == 4:
            break
        decision = entry["evidence"]
        votes = decision["votes"]
        decision["agreed"] = len(votes) == 2 and all(
            v["choice"] == "accept" for v in votes
        )
        selected.append(decision)
    return {
        "activity_decisions": selected,
        "activity_experiences": [
            v for _, v in sorted(experiences, key=lambda p: -p[0])[:4]
        ],
    }


def register(api, actor):
    A = Depends(actor)

    @api.put("/v1/modules/{key}/vote")
    def vote(key: str, form: Vote, request: Request, a: Actor = A):
        s = request.app.state
        with s.records.release_lock, s.db.connection(True) as c:
            activity(c, a, key, form.proposal_version)
            params = (key, form.proposal_version, a.id)
            old = c.execute(
                "SELECT * FROM activity_votes WHERE module_id=? AND proposal_version=? AND owner=?",
                params,
            ).fetchone()
            note = form.note.strip()
            if old and (old["choice"], old["note"]) == (form.choice, note):
                return {"ok": True}
            check_version(old["version"] if old else 0, form.version)
            c.execute(
                """INSERT INTO activity_votes VALUES(?,?,?,?,?,1)
                      ON CONFLICT(module_id,proposal_version,owner) DO UPDATE SET
                      choice=excluded.choice,note=excluded.note,version=version+1""",
                (*params, form.choice, note),
            )
            bump_epoch(c, a)
        return {"ok": True}

    @api.put("/v1/modules/{key}/steps/{step}")
    def milestone(
        key: str,
        step: Literal["saved", "planned", "happened"],
        form: Step,
        request: Request,
        a: Actor = A,
    ):
        s = request.app.state
        with s.records.release_lock, s.db.connection(True) as c:
            activity(c, a, key, form.proposal_version)
            params = (key, a.id, step)
            old = c.execute(
                "SELECT at,version FROM activity_steps WHERE module_id=? AND owner=? AND step=?",
                params,
            ).fetchone()
            if bool(old and old["at"] is not None) == form.enabled:
                return {"ok": True}
            check_version(old["version"] if old else 0, form.version)
            if (
                step == "happened"
                and not form.enabled
                and c.execute(
                    "SELECT 1 FROM activity_reviews WHERE module_id=? AND owner=? AND text IS NOT NULL",
                    (key, a.id),
                ).fetchone()
            ):
                raise Failure(
                    409, "has_feedback", "请先撤回这次体验反馈，再更正发生记录。"
                )
            c.execute(
                """INSERT INTO activity_steps VALUES(?,?,?,?,1)
                      ON CONFLICT(module_id,owner,step) DO UPDATE SET at=excluded.at,version=version+1""",
                (*params, int(time.time()) if form.enabled else None),
            )
        return {"ok": True}

    @api.put("/v1/modules/{key}/review")
    def review(key: str, form: Review, request: Request, a: Actor = A):
        s = request.app.state
        content = text_value(form.text, 600)
        with s.records.release_lock, s.db.connection(True) as c:
            activity(c, a, key, form.proposal_version)
            if not c.execute(
                "SELECT 1 FROM activity_steps WHERE module_id=? AND owner=? AND step='happened' AND at IS NOT NULL",
                (key, a.id),
            ).fetchone():
                raise Failure(
                    409, "experience_required", "请先记录自己实际参加过这次活动。"
                )
            old = c.execute(
                "SELECT * FROM activity_reviews WHERE module_id=? AND owner=?",
                (key, a.id),
            ).fetchone()
            if old and (old["text"], old["scope"]) == (content, form.scope):
                return {"ok": True}
            check_version(old["version"] if old else 0, form.version)
            c.execute(
                """INSERT INTO activity_reviews VALUES(?,?,?,?,1,?)
                      ON CONFLICT(module_id,owner) DO UPDATE SET text=excluded.text,scope=excluded.scope,
                      at=excluded.at,version=version+1""",
                (key, a.id, content, form.scope, int(time.time())),
            )
            bump_epoch(c, a)
        return {"ok": True}

    @api.post("/v1/modules/{key}/review/withdraw")
    def withdraw(key: str, form: Update, request: Request, a: Actor = A):
        s = request.app.state
        with s.records.release_lock, s.db.connection(True) as c:
            activity(c, a, key, form.proposal_version)
            old = c.execute(
                "SELECT version,text FROM activity_reviews WHERE module_id=? AND owner=?",
                (key, a.id),
            ).fetchone()
            if old is None or old["text"] is None:
                return {"ok": True}
            check_version(old["version"], form.version)
            c.execute(
                "UPDATE activity_reviews SET text=NULL,scope='private',version=version+1 WHERE module_id=? AND owner=?",
                (key, a.id),
            )
            bump_epoch(c, a)
        return {"ok": True}
