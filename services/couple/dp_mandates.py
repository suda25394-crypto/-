"""Shared contextual reminders, explicitly confirmed from a visible channel message."""

from __future__ import annotations

import re
import secrets
import unicodedata
from typing import Literal

from fastapi import Depends, Request
from pydantic import BaseModel, ConfigDict, Field

from .business import Actor, Failure, bump_epoch, check_version, missing, text_value


SQL_SCHEMA = """
CREATE TABLE IF NOT EXISTS dp_mandates (
    id TEXT PRIMARY KEY, pair TEXT NOT NULL REFERENCES couples,
    owner TEXT NOT NULL, task TEXT NOT NULL, cue TEXT NOT NULL,
    source_id TEXT NOT NULL, source_owner TEXT NOT NULL, source_text TEXT NOT NULL,
    source_at INTEGER NOT NULL, status TEXT NOT NULL
      CHECK(status IN ('active','paused','completed','cancelled')),
    version INTEGER NOT NULL, UNIQUE(pair,source_id)
);
CREATE INDEX IF NOT EXISTS dp_mandates_active ON dp_mandates(pair,status);
"""

# Aliases connect ordinary questions with the context the couple actually saved.
# Other topics can match the user's own words without a predefined topic code.
_TOPICS = tuple(
    re.compile(pattern)
    for pattern in (
        r"电影|影片|看片|影院|放映|看什么(?:好|呢|呀)?(?:[?？!！。\s]|$)",
        r"吃饭|吃什么|餐厅|用餐|饭店|聚餐",
        r"散步|走走|遛弯",
        r"看书|读书|书单|读什么",
        r"听歌|音乐|听什么|歌单",
        r"旅行|旅游|出游|行程",
        r"看展|展览|美术馆|展馆",
    )
)
_GENERIC = re.compile(
    r"下次|今晚|今天|明天|周末|一起|帮我|帮忙|我们|你们|我俩|两人|两个|时候|想要|可以|打算"
    r"|什么|怎么|如何|选个|挑个|上次|那个|之前|记得|决定|推荐|建议|安排|请问"
)
_SEEKING = re.compile(
    r"推荐|建议|帮.{0,5}(?:找|选|挑|安排|想|计划)|提醒我|想(?:找|选|挑)|选一|挑一"
    r"|(?:看|吃|喝|听|读|玩|做|去|买|选|挑|点|订)(?:点|些|个)?(?:什么|哪[个家里儿些部种天本])"
    r"|(?:怎么|怎样|如何)(?:安排|选|挑|计划)|有没有.{0,16}(?:合适|好[看吃玩去听]|推荐)"
    r"|(?:要不要|好不好|合适吗)|\b(?:recommend|suggest|what\s+should|which\s+should)\b",
    re.I,
)


def _tokens(value):
    value = _GENERIC.sub(" ", unicodedata.normalize("NFKC", value).lower())
    parts = re.findall(r"[\u3400-\u9fff]+|[a-z0-9]{2,}", value)
    terms = set()
    for word in parts:
        if word.isascii():
            terms.add(word)
        else:
            terms.update(word[i : i + 2] for i in range(len(word) - 1))
    return terms


def context(c, a, scope, text):
    matches = []
    if scope not in ("private", "shared") or not _SEEKING.search(text):
        return {"mandates": []}
    query = _tokens(text)
    topics = [pattern for pattern in _TOPICS if pattern.search(text)]
    for row in c.execute(
        """SELECT id,task,cue,source_owner,source_at FROM dp_mandates
        WHERE pair=? AND status='active' ORDER BY rowid DESC""",
        (a.pair,),
    ):
        cue = row["cue"]
        phrase = _tokens(cue)
        aliases = sum(bool(pattern.search(cue)) for pattern in topics)
        overlap = len(query & phrase)
        if aliases or overlap:
            matches.append((4 * aliases + min(overlap, 4), dict(row)))
    matches.sort(key=lambda match: -match[0])
    return {"mandates": [row for _, row in matches[:3]]}


_COLUMNS = (
    "id,owner,task,cue,source_id,source_owner,source_text,source_at,status,version"
)


def state(c, a):
    return {
        "mandates": [
            dict(r)
            for r in c.execute(
                f"SELECT {_COLUMNS} FROM dp_mandates WHERE pair=? ORDER BY rowid DESC",
                (a.pair,),
            )
        ]
    }


class SaveMandate(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    source_id: str = Field(min_length=1, max_length=256)
    source_text: str = Field(min_length=1, max_length=8192)
    task: str = Field(min_length=1, max_length=400)
    cue: str = Field(min_length=1, max_length=160)


class ChangeMandate(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    status: Literal["active", "paused", "completed", "cancelled"]
    version: int = Field(ge=1)


def register(api, actor):
    member = Depends(actor)

    @api.post("/v1/mandates")
    def save(form: SaveMandate, request: Request, a: Actor = member):
        service = request.app.state
        task, cue = text_value(form.task, 400), text_value(form.cue, 160)
        messages = service.up.channel_messages(a.upstream)
        source = next(
            (
                m
                for m in messages
                if m["id"] == form.source_id
                and m["role"] == "user"
                and m["owner"] in (service.settings.a, service.settings.b)
            ),
            None,
        )
        if source is None:
            missing()
        if source["text"] != form.source_text:
            raise Failure(409, "source_changed", "原消息已经更新，请刷新后重新核对。")
        with service.records.release_lock, service.db.connection(True) as c:
            existing = c.execute(
                "SELECT id,task,cue FROM dp_mandates WHERE pair=? AND source_id=?",
                (a.pair, form.source_id),
            ).fetchone()
            if existing:
                if (existing["task"], existing["cue"]) != (task, cue):
                    raise Failure(
                        409, "already_saved", "这条消息已经保存过委托，请查看共同委托。"
                    )
                return {"id": existing["id"]}
            key = secrets.token_urlsafe(18)
            c.execute(
                """INSERT INTO dp_mandates
                (id,pair,owner,task,cue,source_id,source_owner,source_text,source_at,status,version)
                VALUES(?,?,?,?,?,?,?,?,?,'active',1)""",
                (
                    key,
                    a.pair,
                    a.id,
                    task,
                    cue,
                    source["id"],
                    source["owner"],
                    source["text"],
                    source.get("created_at") or 0,
                ),
            )
            bump_epoch(c, a)
            return {"id": key}

    @api.put("/v1/mandates/{key}")
    def change(key: str, form: ChangeMandate, request: Request, a: Actor = member):
        service = request.app.state
        with service.records.release_lock, service.db.connection(True) as c:
            row = c.execute(
                "SELECT version,status FROM dp_mandates WHERE pair=? AND id=?",
                (a.pair, key),
            ).fetchone()
            if not row:
                missing()
            if row["status"] == form.status:
                return {"id": key, "version": row["version"]}
            check_version(row["version"], form.version)
            if row["status"] in ("completed", "cancelled"):
                raise Failure(409, "closed_mandate", "这项委托已经结束。")
            c.execute(
                "UPDATE dp_mandates SET status=?,version=version+1 WHERE pair=? AND id=?",
                (form.status, a.pair, key),
            )
            bump_epoch(c, a)
            return {"id": key, "version": row["version"] + 1}
