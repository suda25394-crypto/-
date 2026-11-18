"""Explicit pair consent for collaborative reflection. Private chat never creates these rows."""

import secrets
from typing import Literal
from fastapi import Depends, Request
from pydantic import BaseModel, ConfigDict, Field
from .business import Actor, Failure, bump_epoch, check_version, missing, text_value
from .database import encode

SQL_SCHEMA = """
CREATE TABLE IF NOT EXISTS reflections(
 id TEXT PRIMARY KEY, pair TEXT NOT NULL REFERENCES couples, owner TEXT NOT NULL, request_id TEXT NOT NULL,
 phase TEXT NOT NULL, version INTEGER NOT NULL, proposal TEXT NOT NULL DEFAULT '', module_id TEXT,
 UNIQUE(pair, owner, request_id));
CREATE UNIQUE INDEX IF NOT EXISTS open_reflection ON reflections(pair) WHERE phase IN ('invited','active');
CREATE TABLE IF NOT EXISTS reflection_members(
 review TEXT NOT NULL REFERENCES reflections, owner TEXT NOT NULL, joined INTEGER NOT NULL DEFAULT 0,
 words TEXT NOT NULL DEFAULT '', approved INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(review,owner));
"""


class Invite(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    request_id: str = Field(pattern=r"^[A-Za-z0-9_-]{8,96}$")
    shared: Literal[True]


class Action(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    action: Literal["join", "leave", "statement", "propose", "approve"]
    version: int = Field(ge=1)
    text: str = Field(default="", max_length=600)


def project(c, a, row):
    members = [
        dict(m)
        for m in c.execute(
            "SELECT owner,joined,words,approved FROM reflection_members WHERE review=? ORDER BY owner",
            (row["id"],),
        )
    ]
    return dict(row) | {"members": members}


def state(c, a):
    row = c.execute(
        "SELECT id,owner,phase,version,proposal,module_id FROM reflections WHERE pair=? AND phase IN ('invited','active')",
        (a.pair,),
    ).fetchone()
    return {"reflections": [project(c, a, row)] if row else []}


def context(c, a):
    return [r for r in state(c, a)["reflections"] if r["phase"] == "active"]


def register(api, actor):
    A = Depends(actor)

    @api.post("/v1/reflections")
    def invite(form: Invite, request: Request, a: Actor = A):
        s = request.app.state
        with s.records.release_lock, s.db.connection(True) as c:
            old = c.execute(
                "SELECT id FROM reflections WHERE pair=? AND owner=? AND request_id=?",
                (a.pair, a.id, form.request_id),
            ).fetchone()
            if old:
                return {"id": old[0]}
            if state(c, a)["reflections"]:
                raise Failure(409, "already_open", "已有待处理复盘，请先打开查看。")
            key = secrets.token_hex(12)
            c.execute(
                "INSERT INTO reflections(id,pair,owner,request_id,phase,version) VALUES(?,?,?,?,'invited',1)",
                (key, a.pair, a.id, form.request_id),
            )
            members = c.execute(
                "SELECT a,b FROM couples WHERE id=?", (a.pair,)
            ).fetchone()
            c.executemany(
                "INSERT INTO reflection_members(review,owner,joined) VALUES(?,?,?)",
                [(key, owner, int(owner == a.id)) for owner in members],
            )
            return {"id": key}

    @api.post("/v1/reflections/{key}")
    def act(key: str, form: Action, request: Request, a: Actor = A):
        s = request.app.state
        with s.records.release_lock, s.db.connection(True) as c:
            row = c.execute(
                "SELECT * FROM reflections WHERE pair=? AND id=?", (a.pair, key)
            ).fetchone()
            if not row:
                missing()
            mine = c.execute(
                "SELECT * FROM reflection_members WHERE review=? AND owner=?",
                (key, a.id),
            ).fetchone()
            op = form.action
            if (op == "leave" and row["phase"] == "closed") or (
                op == "approve" and row["phase"] == "saved" and mine["approved"]
            ):
                return {"ok": True, "module_id": row["module_id"]}
            # Idempotent retries bind to the actual current state, including the proposal revision.
            if (
                row["phase"] in ("invited", "active")
                and op == "join"
                and mine["joined"]
            ):
                return {"ok": True, "phase": row["phase"]}
            if row["phase"] == "active" and (
                (op == "approve" and mine["approved"])
                or (
                    op == "statement"
                    and mine["words"]
                    and mine["words"] == form.text.strip()
                )
                or (
                    op == "propose"
                    and row["proposal"]
                    and row["proposal"] == form.text.strip()
                )
            ):
                return {"ok": True, "phase": row["phase"]}
            check_version(row["version"], form.version)
            if row["phase"] not in ("invited", "active"):
                raise Failure(409, "review_closed", "这次复盘已结束。")
            phase = row["phase"]
            if op == "leave":
                phase = "closed"
                c.execute(
                    "UPDATE reflection_members SET approved=0,words='' WHERE review=?",
                    (key,),
                )
                c.execute("UPDATE reflections SET proposal='' WHERE id=?", (key,))
            elif op == "join":
                c.execute(
                    "UPDATE reflection_members SET joined=1 WHERE review=? AND owner=?",
                    (key, a.id),
                )
                phase = "active"
            elif phase != "active":
                raise Failure(409, "needs_both", "需等双方分别同意复盘。")
            elif op == "statement":
                c.execute(
                    "UPDATE reflection_members SET words=? WHERE review=? AND owner=?",
                    (form.text.strip(), key, a.id),
                )
                c.execute(
                    "UPDATE reflection_members SET approved=0 WHERE review=?", (key,)
                )
            elif op == "propose":
                c.execute(
                    "UPDATE reflections SET proposal=? WHERE id=?",
                    (text_value(form.text, 600), key),
                )
                c.execute(
                    "UPDATE reflection_members SET approved=0 WHERE review=?", (key,)
                )
            elif op == "approve":
                if not row["proposal"]:
                    raise Failure(409, "empty_agreement", "请先核对约定的具体文字。")
                c.execute(
                    "UPDATE reflection_members SET approved=1 WHERE review=? AND owner=?",
                    (key, a.id),
                )
                if (
                    c.execute(
                        "SELECT COUNT(*) FROM reflection_members WHERE review=? AND approved=1",
                        (key,),
                    ).fetchone()[0]
                    == 2
                ):
                    module = secrets.token_hex(12)
                    item = {
                        "module": "memory",
                        "title": "我们确认的约定",
                        "body": row["proposal"],
                    }
                    draft = secrets.token_hex(12)
                    c.execute(
                        "INSERT INTO drafts VALUES(?,?,?,?,?,?,?,?)",
                        (
                            draft,
                            a.pair,
                            a.id,
                            "shared",
                            "confirmed",
                            1,
                            encode([item]),
                            "manual:review:" + key,
                        ),
                    )
                    c.execute(
                        "INSERT INTO modules VALUES(?,?,?,?,?,?,?,?,?)",
                        (
                            module,
                            a.pair,
                            a.id,
                            "memory",
                            item["title"],
                            item["body"],
                            1,
                            draft,
                            0,
                        ),
                    )
                    c.execute(
                        "UPDATE reflections SET module_id=? WHERE id=?", (module, key)
                    )
                    phase = "saved"
            c.execute(
                "UPDATE reflections SET phase=?,version=version+1 WHERE id=?",
                (phase, key),
            )
            bump_epoch(c, a)
            return {"ok": True, "phase": phase}
