"""Three subjective questions. The model writes questions; only the two players supply answers."""

import json
import secrets
import time
from datetime import datetime
from typing import Annotated

from fastapi import Depends, Request
from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from .business import Actor, Failure, check_version, missing
from .conversations import BEIJING
from .database import encode
from .upstream import UpstreamError


SQL_SCHEMA = """
CREATE TABLE IF NOT EXISTS dp_game_requests (
    pair TEXT NOT NULL REFERENCES couples, owner TEXT NOT NULL, request_id TEXT NOT NULL,
    source_ids TEXT NOT NULL, status TEXT NOT NULL, started INTEGER NOT NULL, game_id TEXT, error_code TEXT,
    PRIMARY KEY(pair,owner,request_id)
);
CREATE TABLE IF NOT EXISTS dp_games (
    id TEXT PRIMARY KEY, pair TEXT NOT NULL REFERENCES couples, author TEXT NOT NULL,
    sources TEXT NOT NULL, questions TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS dp_games_pair ON dp_games(pair);
CREATE TABLE IF NOT EXISTS dp_game_turns (
    game_id TEXT NOT NULL REFERENCES dp_games, role TEXT NOT NULL,
    choices TEXT NOT NULL DEFAULT '[null,null,null]', version INTEGER NOT NULL DEFAULT 0,
    locked INTEGER NOT NULL DEFAULT 0, consent INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(game_id,role)
);
"""

Identifier = Annotated[str, StringConstraints(min_length=1, max_length=96)]
Choice = Annotated[int, Field(ge=0, le=2)]


class CreateGame(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")
    request_id: Annotated[str, StringConstraints(pattern=r"^[a-zA-Z0-9_-]{8,96}$")]
    source_ids: list[Identifier] = Field(min_length=1, max_length=3)


class Choices(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")
    choices: list[Choice | None] = Field(min_length=3, max_length=3)
    version: int = Field(ge=0)


def insufficient():
    return Failure(
        422, "insufficient_memories", "这些素材还不够出三道题，请先补充共同回忆再来。"
    )


def invalid_output():
    return Failure(
        502, "game_format", "模型题目未通过素材与选项检查，这次没有开始游戏。"
    )


def load_sources(c, a, ids):
    result = []
    for key in ids:
        row = c.execute(
            "SELECT id,title,body,version FROM modules WHERE id=? AND pair=? AND module='memory'",
            (key, a.pair),
        ).fetchone()
        if row is None:
            missing()
        result.append(dict(row))
    return result


def validate_questions(raw, sources):
    if raw == []:
        raise insufficient()
    if not isinstance(raw, list) or len(raw) != 3:
        raise invalid_output()
    refs = {s["id"]: s for s in sources}
    questions = []
    for q in raw:
        if not isinstance(q, dict) or set(q) != {
            "prompt",
            "options",
            "source_id",
            "anchor",
        }:
            raise invalid_output()
        key = q["source_id"]
        if not isinstance(key, str) or key not in refs:
            raise invalid_output()
        prompt, anchor, opts = q["prompt"], q["anchor"], q["options"]
        if (
            not isinstance(prompt, str)
            or not 1 <= len(prompt.strip()) <= 160
            or not isinstance(anchor, str)
            or not 2 <= len(anchor.strip()) <= 80
            or not any(anchor.strip() in refs[key][name] for name in ("title", "body"))
            or not isinstance(opts, list)
            or len(opts) != 3
            or any(
                not isinstance(o, str) or not 1 <= len(o.strip()) <= 80 for o in opts
            )
        ):
            raise invalid_output()
        opts = [o.strip() for o in opts]
        if len({o.casefold() for o in opts}) != 3:
            raise invalid_output()
        questions.append(
            {
                "prompt": prompt.strip(),
                "options": opts,
                "source_id": key,
                "anchor": anchor.strip(),
            }
        )
    if len({q["prompt"].casefold() for q in questions}) != 3:
        raise invalid_output()
    return questions


def current_sources(c, a, row):
    for key, version in json.loads(row["sources"]):
        if not c.execute(
            "SELECT 1 FROM modules WHERE id=? AND pair=? AND module='memory' AND version=?",
            (key, a.pair, version),
        ).fetchone():
            return False
    return True


def game(c, a, key):
    row = c.execute(
        "SELECT * FROM dp_games WHERE id=? AND pair=?", (key, a.pair)
    ).fetchone()
    if row is None or not current_sources(c, a, row):
        missing()
    return row


def role_for(a, row):
    return "answer" if a.id == row["author"] else "guess"


def view(c, a, row):
    role = role_for(a, row)
    other = "guess" if role == "answer" else "answer"
    turns = {
        r["role"]: r
        for r in c.execute("SELECT * FROM dp_game_turns WHERE game_id=?", (row["id"],))
    }
    mine, theirs = turns[role], turns[other]
    result = {
        "id": row["id"],
        "role": role,
        "questions": json.loads(row["questions"]),
        "my_choices": json.loads(mine["choices"]),
        "version": mine["version"],
        "my_locked": bool(mine["locked"]),
        "other_locked": bool(theirs["locked"]),
        "my_consent": bool(mine["consent"]),
        "other_consent": bool(theirs["consent"]),
    }
    if mine["consent"] and theirs["consent"]:
        answers, guesses = [
            json.loads(turns[r]["choices"]) for r in ("answer", "guess")
        ]
        result["result"] = {
            "answers": answers,
            "guesses": guesses,
            "score": sum(a == b for a, b in zip(answers, guesses)),
        }
    return result


def state(c, a):
    rows = c.execute(
        "SELECT * FROM dp_games WHERE pair=? ORDER BY rowid DESC", (a.pair,)
    )
    pending = c.execute(
        """SELECT status,started FROM dp_game_requests WHERE pair=? AND owner=?
           ORDER BY rowid DESC LIMIT 1""",
        (a.pair, a.id),
    ).fetchone()
    generation = None
    if pending and pending["status"] in ("pending", "unknown"):
        generation = (
            pending["status"] if pending["started"] + 120 > time.time() else "unknown"
        )
    return {
        "games": [view(c, a, r) for r in rows if current_sources(c, a, r)],
        "game_generation_status": generation,
    }


def active_session(c, a):
    if not c.execute(
        "SELECT 1 FROM sessions WHERE digest=? AND pair=? AND owner=? AND expires>?",
        (a.session, a.pair, a.id, int(time.time())),
    ).fetchone():
        raise Failure(401, "unauthorized", "请重新登录。")


def generate(s, a, form):
    ids = sorted(form.source_ids)
    if len(set(ids)) != len(ids):
        raise Failure(422, "invalid_data", "请选择不同的共同回忆。")
    key = (a.pair, a.id, form.request_id)
    where = " WHERE pair=? AND owner=? AND request_id=?"
    with s.db.connection(True) as c:
        active_session(c, a)
        sources = load_sources(c, a, ids)
        req = c.execute("SELECT * FROM dp_game_requests" + where, key).fetchone()
        if req:
            if req["source_ids"] != encode(ids):
                raise Failure(409, "request_conflict", "这个请求已用于另一组素材。")
            if req["status"] == "ready":
                return view(c, a, game(c, a, req["game_id"]))
            if req["status"] == "invalid":
                if req["error_code"] == "source_changed":
                    raise Failure(409, "source_changed", "回忆已更新，请重新选材。")
                raise (
                    insufficient()
                    if req["error_code"] == "insufficient_memories"
                    else invalid_output()
                )
            if req["status"] != "rejected":
                if req["status"] == "unknown" or req["started"] + 120 <= time.time():
                    raise Failure(
                        409,
                        "generation_unknown",
                        "未取得出题回执，此请求不会再次调用模型。",
                    )
                raise Failure(
                    409,
                    "generation_pending",
                    "本次出题已提交，稍后刷新。相同请求不会再次调用模型。",
                )
        if not any(
            len(src[name].strip()) >= 2 for src in sources for name in ("title", "body")
        ):
            raise insufficient()
        day = datetime.now(BEIJING).date().isoformat()
        used = c.execute(
            "SELECT count(*) FROM usage WHERE pair=? AND day=? AND outcome!='rejected'",
            (a.pair, day),
        ).fetchone()[0]
        if used >= s.settings.daily:
            raise Failure(429, "daily_limit", "今天的模型调用额度已用完，明天再试。")
        usage_id = c.execute(
            "INSERT INTO usage(pair,day,request_id,outcome) VALUES(?,?,?,'reserved')",
            (a.pair, day, "game:" + a.id + ":" + form.request_id),
        ).lastrowid
        c.execute(
            """INSERT INTO dp_game_requests(pair,owner,request_id,source_ids,status,started) VALUES(?,?,?,?,'pending',?)
                     ON CONFLICT(pair,owner,request_id) DO UPDATE SET status='pending',started=excluded.started,error_code=NULL""",
            (*key, encode(ids), int(time.time())),
        )
    # Bound the model input independently of the user's original records. Never read turn rows here.
    materials = [
        {"id": src["id"], "title": src["title"], "body": src["body"][:800]}
        for src in sources
    ]
    returned = False
    try:
        raw = s.up.generate_game(a.upstream, materials)
        returned = True
        questions = validate_questions(
            raw.get("questions") if isinstance(raw, dict) else None, materials
        )
        s.up.check_member(a.upstream, a.id)
        with s.db.connection(True) as c:
            active_session(c, a)
            if load_sources(c, a, ids) != sources:
                raise Failure(409, "source_changed", "回忆已更新，请核对后重新选材。")
            game_id = secrets.token_hex(12)
            versions = [[src["id"], src["version"]] for src in sources]
            c.execute(
                "INSERT INTO dp_games VALUES(?,?,?,?,?)",
                (game_id, a.pair, a.id, encode(versions), encode(questions)),
            )
            c.executemany(
                "INSERT INTO dp_game_turns(game_id,role) VALUES(?,?)",
                [(game_id, "answer"), (game_id, "guess")],
            )
            c.execute(
                "UPDATE dp_game_requests SET status='ready',game_id=?" + where,
                (game_id, *key),
            )
            usage = raw.get("usage")

            def tokens(field):
                n = usage.get(field) if isinstance(usage, dict) else None
                return n if type(n) is int and 0 <= n <= 10000000 else None

            c.execute(
                "UPDATE usage SET outcome='returned',in_tokens=?,out_tokens=? WHERE id=?",
                (tokens("prompt_tokens"), tokens("completion_tokens"), usage_id),
            )
            return view(c, a, game(c, a, game_id))
    except (UpstreamError, Failure) as e:
        rejected = not returned and (
            e.status in (400, 401, 403, 413, 422, 429)
            or e.code
            in (
                "model_disabled",
                "model_offline",
                "gateway_disabled",
                "upstream_disabled",
            )
        )
        if e.code=="content_filter":
            rejected=False
        deterministic = e.code in (
            "model_format",
            "game_format",
            "insufficient_memories",
            "source_changed",
        )
        with s.db.connection(True) as c:
            c.execute(
                "UPDATE usage SET outcome=? WHERE id=?",
                (
                    "rejected"
                    if rejected
                    else "returned"
                    if returned or deterministic
                    else "uncertain",
                    usage_id,
                ),
            )
            c.execute(
                "UPDATE dp_game_requests SET status=?,error_code=?" + where,
                (
                    "rejected"
                    if rejected
                    else "invalid"
                    if deterministic
                    else "unknown",
                    e.code,
                    *key,
                ),
            )
        raise


def register(api, actor):
    auth = Depends(actor)

    @api.post("/v1/games")
    def new_game(request: Request, form: CreateGame, a: Actor = auth):
        return generate(request.app.state, a, form)

    def write_choices(request, a, key, form, lock):
        with request.app.state.db.connection(True) as c:
            active_session(c, a)
            row = game(c, a, key)
            snapshot = view(c, a, row)
            if lock and None in form.choices:
                raise Failure(422, "incomplete_turn", "请先选完三道题。")
            if snapshot["my_choices"] == form.choices and (
                not lock or snapshot["my_locked"]
            ):
                return snapshot
            if snapshot["my_locked"]:
                raise Failure(409, "turn_locked", "这一轮选择已提交。")
            check_version(snapshot["version"], form.version)
            c.execute(
                "UPDATE dp_game_turns SET choices=?,locked=?,version=version+1 WHERE game_id=? AND role=?",
                (encode(form.choices), int(lock), key, snapshot["role"]),
            )
            return view(c, a, row)

    @api.put("/v1/games/{key}/choices")
    def choose(request: Request, key: str, form: Choices, a: Actor = auth):
        return write_choices(request, a, key, form, False)

    @api.post("/v1/games/{key}/lock")
    def lock(request: Request, key: str, form: Choices, a: Actor = auth):
        return write_choices(request, a, key, form, True)

    @api.post("/v1/games/{key}/reveal")
    def reveal(request: Request, key: str, a: Actor = auth):
        with request.app.state.db.connection(True) as c:
            active_session(c, a)
            row = game(c, a, key)
            current = view(c, a, row)
            if not (current["my_locked"] and current["other_locked"]):
                raise Failure(409, "need_both_turns", "双方都提交后才可以揭晓。")
            c.execute(
                "UPDATE dp_game_turns SET consent=1 WHERE game_id=? AND role=?",
                (key, current["role"]),
            )
            return view(c, a, row)
