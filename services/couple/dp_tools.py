"""Scoped tool requests; no official provider credential or signed tool history goes to a phone."""

from __future__ import annotations

import base64
import binascii
from datetime import date, datetime, timezone, timedelta
import hashlib
import ipaddress
import json
from pathlib import PurePath
import re
import secrets
import socket
from concurrent.futures import ThreadPoolExecutor, wait
import time
from typing import Annotated, Literal
from urllib.parse import parse_qsl, urlsplit

from fastapi import Depends, Request
from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from .business import Actor, Failure, clean_items, missing, read_epoch, text_value
from .database import encode
from .dp_game import active_session
from .upstream import UpstreamError

SQL_SCHEMA = """
CREATE TABLE IF NOT EXISTS tool_media(id TEXT PRIMARY KEY,pair TEXT NOT NULL REFERENCES couples,owner TEXT NOT NULL,
 scope TEXT NOT NULL,module_id TEXT,name TEXT NOT NULL,mime TEXT NOT NULL,data BLOB NOT NULL,
 size INTEGER NOT NULL,expires INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS tool_media_expiry ON tool_media(expires);
CREATE TABLE IF NOT EXISTS tool_turns(id TEXT PRIMARY KEY,pair TEXT NOT NULL REFERENCES couples,owner TEXT NOT NULL,
 scope TEXT NOT NULL,module_id TEXT,kind TEXT NOT NULL,request_id TEXT NOT NULL,fingerprint TEXT NOT NULL,
 attachment_id TEXT,epoch INTEGER NOT NULL,status TEXT NOT NULL,at INTEGER NOT NULL,result BLOB,history BLOB,
 draft_id TEXT,charge_id INTEGER,UNIQUE(pair,owner,request_id));
CREATE INDEX IF NOT EXISTS tool_thread ON tool_turns(pair,scope,module_id,at);
"""
Scope = Literal["private", "shared"]
Identifier = Annotated[str, StringConstraints(min_length=1, max_length=128)]
RequestID = Annotated[str, StringConstraints(pattern=r"^[a-zA-Z0-9_-]{8,96}$")]
Tool = Literal[
    "web",
    "image_search",
    "deep_search",
    "read_url",
    "search",
    "fetch",
    "vision",
    "parse_text",
    "parse_rich",
    "ocr",
    "poster_draft",
    "asr",
    "tts",
    "title",
]
PUBLIC = {"web", "image_search", "deep_search", "read_url", "search", "fetch"}
WEB_CONTEXT = {"web", "image_search", "deep_search", "read_url"}
FILES = {"vision", "poster_draft", "ocr", "parse_text", "parse_rich", "asr"}
MAX_FILE = 4 * 1024 * 1024
MIME = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".pdf": "application/pdf",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".doc": "application/msword",
    ".ppt": "application/vnd.ms-powerpoint",
    ".xls": "application/vnd.ms-excel",
    ".txt": "text/plain",
    ".md": "text/markdown",
    ".csv": "text/csv",
    ".wav": "audio/wav",
    ".ogg": "audio/ogg",
    ".opus": "audio/ogg",
}


class Strict(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")


class Thread(Strict):
    scope: Scope
    module_id: Identifier | None = None


class Attachment(Thread):
    name: str = Field(min_length=1, max_length=128)
    mime: str = Field(min_length=1, max_length=120)
    data_b64: str = Field(min_length=4, max_length=4 * ((MAX_FILE + 2) // 3))


class Tags(Strict):
    date: str | None = Field(default=None, max_length=10)
    language: str | None = Field(default=None, max_length=32)
    region: str | None = Field(default=None, max_length=60)


class ToolForm(Thread):
    request_id: RequestID
    kind: Tool
    text: str = Field(default="", max_length=2000)
    attachment_id: Identifier | None = None
    previous_id: Identifier | None = None
    context: Tags | None = None


def invalid(msg):
    raise Failure(422, "invalid_tool", msg)


_RESOLVER = ThreadPoolExecutor(max_workers=4, thread_name_prefix="public-tool-dns")
_SENSITIVE_PARAMETER = re.compile(
    r"(token|password|credential|signature|authorization|api.?key|session|secret)", re.I
)
_URL = re.compile(r"https?://[^\s，。！？））<>]+", re.I)


def public_host(url):
    try:
        u = urlsplit(url)
        host = (u.hostname or "").lower().rstrip(".")
        if (
            len(url) > 2048
            or any(ch.isspace() or ord(ch) < 32 or ch == "\\" for ch in url)
            or u.scheme not in ("https", "http")
            or u.username is not None
            or u.password is not None
            or u.port not in (None, 443, 80)
            or u.fragment
            or "%" in host
            or any(
                _SENSITIVE_PARAMETER.search(k)
                for k, _ in parse_qsl(u.query, keep_blank_values=True)
            )
        ):
            return None
        try:
            ip = ipaddress.ip_address(host)
            return host if ip.is_global and not ip.is_multicast else None
        except ValueError:
            pass
        if (
            not re.fullmatch(r"[a-z0-9.-]+", host)
            or "." not in host
            or host.endswith(
                (
                    ".local",
                    ".internal",
                    ".localhost",
                    ".test",
                    ".invalid",
                    ".onion",
                    ".lan",
                    ".home",
                    ".arpa",
                )
            )
            or any(
                not part or len(part) > 63 or part.startswith("-") or part.endswith("-")
                for part in host.split(".")
            )
            or re.fullmatch(r"(?:0x[0-9a-f]+|[0-9.]+)", host)
        ):
            return None
        return host
    except (TypeError, ValueError):
        return None


def public_dns(host):
    try:
        addrs = {
            ipaddress.ip_address(item[4][0])
            for item in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
        }
        return bool(addrs) and all(ip.is_global and not ip.is_multicast for ip in addrs)
    except (ValueError, OSError):
        return False


def public_urls(urls):
    targets = {url: public_host(url) for url in urls if isinstance(url, str)}
    tasks = {h: _RESOLVER.submit(public_dns, h) for h in set(targets.values()) if h}
    if tasks:
        _, pending = wait(tasks.values(), timeout=4)
        for f in pending:
            f.cancel()
    return {
        url
        for url, h in targets.items()
        if h and tasks[h].done() and not tasks[h].cancelled() and tasks[h].result()
    }


def media_access(c, a, key, scope, module_id):
    row = c.execute(
        """SELECT * FROM tool_media WHERE id=? AND pair=? AND scope=? AND module_id IS ?
      AND (owner=? OR (scope='shared' AND mime NOT LIKE 'audio/%')) AND expires>?""",
        (key, a.pair, scope, module_id, a.id, int(time.time())),
    ).fetchone()
    if not row:
        missing()
    return row


def view(c, s, a, key, scope=None, module_id=None, strict_thread=False):
    row = c.execute(
        """SELECT * FROM tool_turns WHERE id=? AND pair=? AND
       (owner=? OR (scope='shared' AND kind NOT IN ('asr','tts'))) AND status='ready'""",
        (key, a.pair, a.id),
    ).fetchone()
    if (
        not row
        or strict_thread
        and (row["scope"] != scope or row["module_id"] != module_id)
    ):
        missing()
    if row["attachment_id"]:
        media_access(c, a, row["attachment_id"], row["scope"], row["module_id"])
    return row, json.loads(s.settings.encryption.decrypt(row["result"]))


def forget_media(c, key):
    drafts = c.execute(
        "SELECT draft_id FROM tool_turns WHERE attachment_id=? AND draft_id IS NOT NULL",
        (key,),
    ).fetchall()
    for d in drafts:
        c.execute(
            "UPDATE drafts SET status='cancelled',version=version+1,items='[]' WHERE id=? AND status='pending'",
            (d["draft_id"],),
        )
    c.execute(
        "UPDATE tool_turns SET status='expired',result=NULL,history=NULL WHERE attachment_id=?",
        (key,),
    )
    c.execute("DELETE FROM tool_media WHERE id=?", (key,))


def expire(c):
    for row in c.execute(
        "SELECT id FROM tool_media WHERE expires<=?", (int(time.time()),)
    ).fetchall():
        forget_media(c, row["id"])


def purge_expired(db):
    with db.connection(True) as c:
        expire(c)


def file_kind(form):
    name = form.name.strip()
    if (
        name in (".", "..")
        or any(ch in name for ch in ("/", "\\", ":", "\x00"))
        or any(ord(c) < 32 for c in name)
    ):
        invalid("请使用不含路径的文件名。")
    ext = PurePath(name).suffix.lower()
    mime = MIME.get(ext)
    aliases = {
        "audio/x-wav": "audio/wav",
        "application/ogg": "audio/ogg",
        "audio/opus": "audio/ogg",
        "image/jpg": "image/jpeg",
    }
    if not mime or aliases.get(form.mime, form.mime) not in (
        mime,
        "application/octet-stream",
    ):
        invalid("此文件类型或 MIME 暂不支持。")
    try:
        data = base64.b64decode(form.data_b64, validate=True)
    except (ValueError, binascii.Error):
        invalid("附件编码不正确。")
    if not 0 < len(data) <= MAX_FILE:
        invalid("请选择 4 MiB 以内的非空文件。")
    magic = {
        ".png": b"\x89PNG\r\n\x1a\n",
        ".jpg": b"\xff\xd8",
        ".jpeg": b"\xff\xd8",
        ".webp": b"RIFF",
        ".pdf": b"%PDF-",
        ".wav": b"RIFF",
        ".ogg": b"OggS",
        ".opus": b"OggS",
    }
    if ext in magic and not data.startswith(magic[ext]):
        invalid("文件格式与内容不符。")
    if (
        ext == ".wav"
        and data[8:12] != b"WAVE"
        or ext == ".webp"
        and data[8:12] != b"WEBP"
    ):
        invalid("文件头不符合格式。")
    return name, mime, data


def reminder(tags):
    if not tags:
        return None
    if tags.date:
        try:
            date.fromisoformat(tags.date)
        except ValueError:
            invalid("日期格式无效。")
    values = [v for v in (tags.date, tags.language, tags.region) if v]
    if any(not re.fullmatch(r"[\w .,/()\-\u3400-\u9fff]+", v) for v in values):
        invalid("语言或地区包含不支持的字符。")
    return ", ".join(values) or None


def request_tool(s, a, f):
    key = (a.pair, a.id, f.request_id)
    digest = hashlib.sha256(encode(f.model_dump()).encode()).hexdigest()
    payload = {"text": f.text.strip()}
    if meta := reminder(f.context):
        payload["reminder"] = meta
    if f.kind in PUBLIC:
        tx = payload["text"]
        if re.search(
            r"(?i)\b(?:bearer\s+|sk-[a-z0-9_-]{16}|gh[pousr]_[a-z0-9_]{16})|[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}|(?<!\d)1[3-9]\d{9}(?!\d)",
            tx,
        ):
            invalid("请移除联系方式或凭据，只保留公开检索词。")
        urls = (
            [tx]
            if f.kind in ("fetch", "read_url") and not f.previous_id
            else _URL.findall(tx)
        )
        if len(urls) > 6 or set(urls) - public_urls(urls):
            invalid("只支持 DNS 可核验的公网网页地址。")
        if f.kind in ("web", "image_search", "deep_search") and len(tx) > 512:
            invalid("请把检索词缩短到 512 字符以内。")
        if f.kind in {"web", "deep_search"} and not f.previous_id and len(tx) > 128:
            invalid("首次网页检索最多 128 个公开字符。")
    if f.kind in PUBLIC and not payload["text"]:
        invalid("请输入愿意交给搜索工具的公开关键词或链接。")
    if f.kind == "search" and len(payload["text"]) > 128:
        invalid("公开搜索词最多 128 个字符。")
    if f.kind in ("tts", "title") and not (payload["text"] or f.previous_id):
        invalid("请输入或选择要处理的文字。")
    if (f.kind in FILES and not f.attachment_id) or (
        f.attachment_id and f.kind not in FILES | {"image_search"}
    ):
        invalid("该操作需要匹配的附件。")
    if f.previous_id and f.attachment_id:
        invalid("请选择同一来源追问或单独提交新附件。")
    attachment_id = f.attachment_id
    prior_sources = []
    now = int(time.time())
    with s.db.connection(True) as c:
        active_session(c, a)
        expire(c)
        if f.module_id:
            s.records.module(c, a, f.module_id)
        prior = c.execute(
            "SELECT * FROM tool_turns WHERE pair=? AND owner=? AND request_id=?", key
        ).fetchone()
        if prior:
            if prior["fingerprint"] != digest:
                raise Failure(409, "request_conflict", "该请求号对应不同内容。")
            if prior["status"] == "ready":
                return view(c, s, a, prior["id"])[1]
            if prior["status"] != "rejected":
                raise Failure(
                    409,
                    "tool_outcome_unknown",
                    "此次请求已经提交，请刷新。没有回执的请求不会自动重发。",
                )
        epoch = read_epoch(c, a)
        if f.attachment_id:
            file = media_access(c, a, f.attachment_id, f.scope, f.module_id)
            mime = file["mime"]
            if (
                f.kind == "asr"
                and not mime.startswith("audio/")
                or f.kind in ("vision", "poster_draft", "image_search")
                and not mime.startswith("image/")
                or f.kind == "ocr"
                and not (mime.startswith("image/") or mime == "application/pdf")
                or f.kind in ("parse_text", "parse_rich")
                and mime.startswith("audio/")
            ):
                invalid("附件与所选工具不匹配。")
            payload["file"] = {
                "name": file["name"],
                "mime": mime,
                "data_b64": base64.b64encode(
                    s.settings.encryption.decrypt(file["data"])
                ).decode(),
            }
        if f.previous_id:
            prev, prior_result = view(
                c, s, a, f.previous_id, f.scope, f.module_id, True
            )
            if prev["epoch"] != epoch:
                raise Failure(
                    409, "context_changed", "授权或资料已变化，请重新选择来源。"
                )
            if (
                f.scope == "shared"
                and prev["kind"] in {"asr", "tts"}
                and f.kind != "tts"
            ):
                invalid(
                    "待修订的语音内容只对本人可见。请先修订并主动发送，再生成共同内容。"
                )
            attachment_id = prev["attachment_id"]
            prior_sources = prior_result["sources"]
            if (
                f.kind in WEB_CONTEXT
                and prev["kind"] in WEB_CONTEXT
                and prev["history"]
            ):
                payload["history"] = json.loads(
                    s.settings.encryption.decrypt(prev["history"])
                )
            elif f.kind in {"web", "read_url", "deep_search"} and prev["kind"] in {
                "search",
                "fetch",
            }:
                payload["history"] = [
                    {"role": "user", "content": "请阅读我选择的公开来源。"},
                    {
                        "role": "assistant",
                        "content": prior_result["text"][:12000]
                        + "\n"
                        + encode(prior_sources),
                    },
                ]
            elif f.kind in ("tts", "title"):
                payload["text"] = text_value(prior_result["text"], 2000)
            else:
                invalid("这个工具不支持所选的上轮结果。")
        day = datetime.now(timezone(timedelta(hours=8))).date().isoformat()
        used = c.execute(
            "SELECT count(*) FROM usage WHERE pair=? AND day=? AND outcome!='rejected'",
            (a.pair, day),
        ).fetchone()[0]
        steps = (
            2
            if f.kind in {"parse_text", "parse_rich"}
            or (not f.previous_id and f.kind in {"web", "read_url", "deep_search"})
            else 1
        )
        if used + steps > s.settings.daily:
            raise Failure(429, "daily_limit", "今日剩余额度不足以完成这次操作。")
        charge = c.execute(
            "INSERT INTO usage(pair,day,request_id,outcome) VALUES(?,?,?,'reserved')",
            (a.pair, day, "tool:" + f.request_id),
        ).lastrowid
        extra = None
        if steps == 2:
            extra = c.execute(
                "INSERT INTO usage(pair,day,request_id,outcome) VALUES(?,?,?,'reserved')",
                (a.pair, day, "tool-source:" + f.request_id),
            ).lastrowid
        rid = secrets.token_hex(16) if not prior else prior["id"]
        c.execute(
            """INSERT INTO tool_turns(id,pair,owner,scope,module_id,kind,request_id,fingerprint,attachment_id,epoch,status,at,charge_id)
        VALUES(?,?,?,?,?,?,?,?,?,?,'reserved',?,?) ON CONFLICT(pair,owner,request_id) DO UPDATE SET status='reserved',charge_id=excluded.charge_id,at=excluded.at,epoch=excluded.epoch""",
            (
                rid,
                a.pair,
                a.id,
                f.scope,
                f.module_id,
                f.kind,
                f.request_id,
                digest,
                attachment_id,
                epoch,
                now,
                charge,
            ),
        )
    try:
        response = s.up.official_tool(a.upstream, f.kind, payload)
        if (
            not isinstance(response, dict)
            or not isinstance(response.get("text"), str)
            or not isinstance(response.get("sources"), list)
        ):
            raise Failure(502, "tool_incomplete", "工具没有完整返回结果。")
        history = response.pop("history", None)
        public = {
            k: response[k]
            for k in (
                "text",
                "title",
                "mime",
                "audio_b64",
                "usage",
                "meter",
                "search_mode",
            )
            if k in response
        }
        refs = [
            src
            for src in (response["sources"] or prior_sources)[:30]
            if isinstance(src, dict)
        ]
        safe = public_urls(
            [
                url
                for src in refs
                for url in (src.get("url"), src.get("image_url"))
                if isinstance(url, str)
            ]
        )
        public["sources"] = [
            {
                "url": src["url"],
                "title": str(src.get("title") or src["url"])[:240],
                **(
                    {"image_url": src["image_url"]}
                    if src.get("image_url") in safe
                    else {}
                ),
            }
            for src in refs
            if src.get("url") in safe
        ]
        public.update(
            id=rid,
            kind=f.kind,
            owner=a.id,
            scope=f.scope,
            module_id=f.module_id,
            created_at=now,
        )
        draft = None
        if f.kind == "poster_draft":
            poster = json.loads(public["text"])
            evidence = text_value(poster["evidence"], 600)
            draft = clean_items(
                [
                    {
                        "module": "date",
                        "title": poster["title"],
                        "body": str(poster["body"])
                        + "\n海报摘录："
                        + evidence
                        + "\n附件："
                        + file["name"],
                    }
                ]
            )
            public["text"] = draft[0]["body"]
        s.up.check_member(a.upstream, a.id)
        with s.records.release_lock, s.db.connection(True) as c:
            active_session(c, a)
            if read_epoch(c, a) != epoch:
                raise Failure(409, "context_changed", "授权已变化，请重新操作。")
            if attachment_id:
                media_access(c, a, attachment_id, f.scope, f.module_id)
            if f.previous_id:
                view(c, s, a, f.previous_id, f.scope, f.module_id, True)
            if draft:
                s.records.materialize(
                    c,
                    a,
                    "tool:" + rid,
                    f.scope,
                    {"items": draft, "memories": [], "reply": public["text"]},
                )
                public["draft_id"] = c.execute(
                    "SELECT id FROM drafts WHERE pair=? AND owner=? AND source=?",
                    (a.pair, a.id, "tool:" + rid),
                ).fetchone()[0]
            usage = public.get("usage") or {}
            c.execute(
                "UPDATE usage SET outcome='returned',in_tokens=?,out_tokens=? WHERE id=?",
                (
                    usage.get("input_tokens", usage.get("prompt_tokens")),
                    usage.get("output_tokens", usage.get("completion_tokens")),
                    charge,
                ),
            )
            if extra:
                extra_used = f.kind in {"parse_text", "parse_rich"} or any(
                    m.get("unit") == "requests" for m in public.get("meter", [])
                )
                c.execute(
                    "UPDATE usage SET outcome=? WHERE id=?",
                    ("returned" if extra_used else "rejected", extra),
                )
            c.execute(
                "UPDATE tool_turns SET status='ready',result=?,history=?,draft_id=? WHERE id=?",
                (
                    s.settings.encryption.encrypt(encode(public).encode()),
                    s.settings.encryption.encrypt(encode(history).encode())
                    if history
                    else None,
                    public.get("draft_id"),
                    rid,
                ),
            )
        return public
    except (Failure, UpstreamError, TypeError, ValueError, KeyError, IndexError) as exc:
        code = getattr(exc, "code", "tool_incomplete")
        rejected = code in (
            "model_access",
            "daily_limit",
            "upstream_disabled",
            "model_disabled",
            "multistep_budget_blocked",
        )
        with s.db.connection(True) as c:
            c.execute(
                "UPDATE usage SET outcome=? WHERE id IN (?,?)",
                ("rejected" if rejected else "uncertain", charge, extra),
            )
            c.execute(
                "UPDATE tool_turns SET status=? WHERE id=?",
                ("rejected" if rejected else "unknown", rid),
            )
        if isinstance(exc, (Failure, UpstreamError)):
            raise
        raise Failure(502, "tool_incomplete", "工具回执不完整，未写入业务。") from None


def register(api, actor):
    auth = Depends(actor)

    @api.post("/v1/ai/attachments")
    def upload(form: Attachment, request: Request, a: Actor = auth):
        s = request.app.state
        name, mime, data = file_kind(form)
        key = secrets.token_hex(16)
        end = int(time.time()) + 3600
        with s.db.connection(True) as c:
            expire(c)
            active_session(c, a)
            if form.module_id:
                s.records.module(c, a, form.module_id)
            if (
                c.execute(
                    "SELECT coalesce(sum(size),0) FROM tool_media WHERE pair=? AND owner=?",
                    (a.pair, a.id),
                ).fetchone()[0]
                + len(data)
                > 24 * 1024 * 1024
            ):
                raise Failure(
                    413, "storage_limit", "附件空间暂满，请删除不再使用的附件。"
                )
            c.execute(
                "INSERT INTO tool_media VALUES(?,?,?,?,?,?,?,?,?,?)",
                (
                    key,
                    a.pair,
                    a.id,
                    form.scope,
                    form.module_id,
                    name,
                    mime,
                    s.settings.encryption.encrypt(data),
                    len(data),
                    end,
                ),
            )
        return {
            "id": key,
            "name": name,
            "mime": mime,
            "expires_at": end,
            "owner": a.id,
            "scope": form.scope,
        }

    @api.get("/v1/ai/attachments")
    def list_files(
        request: Request, scope: Scope, module_id: str | None = None, a: Actor = auth
    ):
        s = request.app.state
        with s.db.connection(True) as c:
            expire(c)
            rows = c.execute(
                """SELECT id,name,mime,scope,owner,expires AS expires_at FROM tool_media
                WHERE pair=? AND scope=? AND module_id IS ? AND (owner=? OR (scope='shared' AND mime NOT LIKE 'audio/%'))
                ORDER BY expires DESC LIMIT 100""",
                (a.pair, scope, module_id, a.id),
            ).fetchall()
        return {"attachments": [dict(r) for r in rows]}

    @api.delete("/v1/ai/attachments/{key}")
    def remove(key: str, request: Request, a: Actor = auth):
        s = request.app.state
        with s.records.release_lock, s.db.connection(True) as c:
            row = c.execute(
                "SELECT owner FROM tool_media WHERE pair=? AND id=?", (a.pair, key)
            ).fetchone()
            if not row or row["owner"] != a.id:
                missing()
            forget_media(c, key)
        return {"deleted": True}

    @api.post("/v1/ai/tools")
    def invoke(form: ToolForm, request: Request, a: Actor = auth):
        return request_tool(request.app.state, a, form)

    @api.get("/v1/ai/tools")
    def list_results(
        request: Request, scope: Scope, module_id: str | None = None, a: Actor = auth
    ):
        s = request.app.state
        with s.db.connection(True) as c:
            expire(c)
            rows = c.execute(
                """SELECT id,kind,at,owner FROM tool_turns WHERE pair=? AND scope=? AND module_id IS ? AND status='ready'
            AND (owner=? OR (scope='shared' AND kind NOT IN ('asr','tts'))) ORDER BY at DESC,rowid DESC LIMIT 40""",
                (a.pair, scope, module_id, a.id),
            ).fetchall()
        return {"results": [dict(r) for r in rows]}

    @api.get("/v1/ai/tools/{key}")
    def get_result(key: str, request: Request, a: Actor = auth):
        s = request.app.state
        with s.db.connection(True) as c:
            expire(c)
            return view(c, s, a, key)[1]
