"""Product API. Run one worker behind Muse's HTTPS reverse proxy."""

from __future__ import annotations

import hashlib
import re
import secrets
import time
from contextlib import asynccontextmanager
from typing import Annotated, Literal

from cryptography.fernet import InvalidToken
from fastapi import Depends, FastAPI, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from .business import Actor, Failure, Records, invalid, text_value
from .conversations import Conversations
from . import dp_activity, dp_mandates, dp_game
from .database import Database, Settings, SCHEMA_VERSION
from .upstream import Upstream, UpstreamError


def failure(status, code, message):
    return JSONResponse(
        {"error": {"code": code, "message": message}},
        status_code=status,
        headers={"Cache-Control": "no-store"},
    )


class BodyLimit:
    """Limit actual streamed bytes including clients that omit Content-Length."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["method"] not in ("POST", "PUT", "PATCH"):
            await self.app(scope, receive, send)
            return
        parts = []
        length = 0
        while True:
            chunk = await receive()
            if chunk["type"] == "http.disconnect":
                return
            data = chunk.get("body", b"")
            length += len(data)
            if length > 32768:
                await failure(413, "body_limit", "提交内容过长。")(scope, receive, send)
                return
            parts.append(data)
            if not chunk.get("more_body"):
                break
        body = b"".join(parts)
        delivered = False

        async def read():
            nonlocal delivered
            if delivered:
                return await receive()
            delivered = True
            return {"type": "http.request", "body": body, "more_body": False}

        await self.app(scope, read, send)


class Form(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class Login(Form):
    email: str = Field(min_length=1, max_length=254)
    password: str = Field(min_length=1, max_length=1024)


class Message(Form):
    scope: Literal["private", "shared"]
    text: str = Field(min_length=1, max_length=2000)
    request_id: Annotated[str, StringConstraints(pattern=r"^[a-zA-Z0-9_-]{8,96}$")]


class Version(Form):
    version: int = Field(ge=0, le=2147483647)


class ModuleMessage(Message):
    version: int = Field(ge=1, le=2147483647)


class Profile(Version):
    published: bool
    data: dict


class Memory(Version):
    text: str = Field(min_length=1, max_length=300)
    scope: Literal["private", "shared"]


class Draft(Version):
    items: list[dict] | None = Field(default=None, max_length=8)


class ModuleUpdate(Version):
    title: str = Field(min_length=1, max_length=120)
    body: str = Field(min_length=1, max_length=2500)


class NewModule(Form):
    request_id: Annotated[str, StringConstraints(pattern=r"^[a-zA-Z0-9_-]{8,96}$")]
    module: Literal["date", "wish", "calendar", "memory"]
    title: str = Field(min_length=1, max_length=120)
    body: str = Field(min_length=1, max_length=2500)
    confirmed: bool


def create_app(settings=None, upstream=None):
    @asynccontextmanager
    async def lifespan(app):
        config = settings or Settings.environment()
        db = Database(config)
        client = upstream or Upstream.from_env()
        records = Records(db)
        app.state.settings, app.state.db, app.state.up, app.state.records = (
            config,
            db,
            client,
            records,
        )
        app.state.chat = Conversations(db, records, client)
        try:
            yield
        finally:
            if upstream is None and hasattr(client, "close"):
                client.close()

    api = FastAPI(
        title="Couple private API",
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )
    api.add_middleware(BodyLimit)

    @api.middleware("http")
    async def no_cache(request, call_next):
        res = await call_next(request)
        res.headers["Cache-Control"] = "no-store"
        res.headers["X-Content-Type-Options"] = "nosniff"
        return res

    @api.exception_handler(Failure)
    @api.exception_handler(UpstreamError)
    async def product_error(request, exc):
        return failure(exc.status, exc.code, exc.message)

    @api.exception_handler(RequestValidationError)
    async def wrong_body(request, exc):
        # FastAPI's default payload echoes input values, sometimes a password.
        return failure(422, "invalid_data", "提交的字段或版本不符合要求。")

    def principal(request: Request, validate=True):
        header = request.headers.get("authorization", "")
        if not re.fullmatch(r"Bearer [A-Za-z0-9_-]{43,100}", header):
            raise Failure(401, "unauthorized", "请重新登录。")
        digest = hashlib.sha256(header[7:].encode()).hexdigest()
        s = request.app.state
        with s.db.connection() as c:
            row = c.execute(
                """SELECT s.*,u.name FROM sessions s JOIN users u ON u.pair=s.pair AND u.id=s.owner
                WHERE s.digest=? AND s.pair=? AND expires>?""",
                (digest, s.settings.pair, int(time.time())),
            ).fetchone()
        if not row:
            raise Failure(401, "unauthorized", "登录已过期，请重新登录。")
        try:
            token = s.settings.encryption.decrypt(row["upstream"]).decode()
        except InvalidToken:
            raise Failure(401, "unauthorized", "登录凭据已更新，请重新登录。") from None
        if validate:
            s.up.check_member(token, row["owner"])
        return Actor(row["owner"], row["name"], row["pair"], token, digest)

    def actor(request: Request):
        return principal(request)

    A = Depends(actor)
    for feature in (dp_activity, dp_mandates, dp_game):
        feature.register(api, actor)

    @api.get("/v1/health")
    def health(request: Request):
        with request.app.state.db.connection() as c:
            c.execute("SELECT 1 FROM couples LIMIT 1").fetchone()
        return {
            "ok": True,
            "schema": SCHEMA_VERSION,
            "mode": request.app.state.settings.mode,
        }

    @api.post("/v1/login")
    def login(form: Login, request: Request):
        s = request.app.state
        account = s.up.login(form.email, form.password)
        uid = account.get("id")
        if uid not in (s.settings.a, s.settings.b):
            raise Failure(403, "not_paired", "此账号不属于这组配对。")
        s.up.check_member(account["token"], uid)
        name = text_value(account.get("name") or uid, 200)
        token = secrets.token_urlsafe(40)
        digest = hashlib.sha256(token.encode()).hexdigest()
        now = int(time.time())
        with s.db.connection(True) as c:
            c.execute("DELETE FROM sessions WHERE expires<=?", (now,))
            c.execute(
                "INSERT INTO users VALUES(?,?,?) ON CONFLICT(pair,id) DO UPDATE SET name=excluded.name",
                (s.settings.pair, uid, name),
            )
            c.execute(
                "INSERT INTO sessions VALUES(?,?,?,?,?)",
                (
                    digest,
                    s.settings.pair,
                    uid,
                    s.settings.encryption.encrypt(account["token"].encode()),
                    now + 7 * 86400,
                ),
            )
        return {
            "token": token,
            "user": {"id": uid, "name": name},
            "paired": True,
            "mode": s.settings.mode,
        }

    @api.post("/v1/logout")
    def logout(request: Request):
        # An offline Open WebUI should never prevent product-session revocation.
        a = principal(request, False)
        with request.app.state.db.connection(True) as c:
            c.execute("DELETE FROM sessions WHERE digest=?", (a.session,))
        try:
            request.app.state.up.signout(a.upstream)
        except UpstreamError:
            pass  # Local product session has already been irrevocably revoked.
        return {"ok": True}

    @api.get("/v1/state")
    def state(request: Request, a: Actor = A):
        s = request.app.state
        shared = []
        for message in s.up.channel_messages(a.upstream):
            shared.append(
                {
                    "id": message["id"],
                    "owner": message["owner"],
                    "role": message["role"],
                    "text": message["text"],
                    "created_at": message.get(
                        "created_at", message.get("createdAt", 0)
                    ),
                }
            )
        with s.db.connection() as c:
            c.execute("BEGIN")
            return {
                "user": {"id": a.id, "name": a.name},
                "paired": True,
                "mode": s.settings.mode,
                **dp_activity.state(c, a),
                **dp_mandates.state(c, a),
                **dp_game.state(c, a),
                "profiles": s.records.profiles(c, a),
                "memories": s.records.memories(c, a),
                "drafts": s.records.drafts(c, a),
                "modules": s.records.modules(c, a),
                "pending_messages": [
                    {
                        "request_id": m["request_id"],
                        "scope": m["scope"],
                        "module_id": m["module_id"],
                        "version": m["module_version"],
                        "text": m["input"],
                        "uncertain": bool(
                            m["uncertain"] and m["busy_until"] <= time.time()
                        ),
                        "busy": m["busy_until"] > time.time(),
                    }
                    for m in c.execute(
                        "SELECT request_id,scope,input,uncertain,busy_until,module_id,module_version FROM chats WHERE pair=? AND owner=? AND done=0 AND (module_id IS NULL OR EXISTS(SELECT 1 FROM modules m WHERE m.id=chats.module_id AND m.pair=chats.pair AND m.version=chats.module_version)) ORDER BY rowid",
                        (a.pair, a.id),
                    )
                ],
                "messages": {"private": s.chat.private_history(c, a), "shared": shared},
            }

    @api.post("/v1/messages")
    def post(form: Message, request: Request, a: Actor = A):
        request.app.state.chat.send(
            a, form.request_id, form.scope, text_value(form.text, 2000)
        )
        return {"ok": True}

    @api.put("/v1/profile")
    def set_profile(form: Profile, request: Request, a: Actor = A):
        request.app.state.records.profile_write(
            a, form.version, form.data, form.published
        )
        return {"ok": True}

    @api.post("/v1/profile/withdraw")
    def withdraw(form: Version, request: Request, a: Actor = A):
        request.app.state.records.profile_write(a, form.version, action="withdraw")
        return {"ok": True}

    @api.delete("/v1/profile")
    def delete_profile(request: Request, version: int = Query(ge=0), a: Actor = A):
        request.app.state.records.profile_write(a, version, action="delete")
        return {"ok": True}

    @api.put("/v1/memories/{key}")
    def update_memory(key: str, form: Memory, request: Request, a: Actor = A):
        request.app.state.records.memory_write(
            a, key, form.version, form.text, form.scope
        )
        return {"ok": True}

    @api.delete("/v1/memories/{key}")
    def delete_memory(
        key: str, request: Request, version: int = Query(ge=1), a: Actor = A
    ):
        request.app.state.records.memory_write(a, key, version)
        return {"ok": True}

    @api.post("/v1/drafts/{key}/{action}")
    def resolve(
        key: str,
        action: Literal["confirm", "cancel"],
        form: Draft,
        request: Request,
        a: Actor = A,
    ):
        request.app.state.records.resolve_draft(
            a, key, form.version, form.items, action
        )
        return {"ok": True}

    @api.post("/v1/modules")
    def new_module(form: NewModule, request: Request, a: Actor = A):
        if not form.confirmed:
            invalid()
        request.app.state.records.manual_module(
            a, form.request_id, form.module, form.title, form.body
        )
        return {"ok": True}

    @api.put("/v1/modules/{key}")
    def edit(key: str, form: ModuleUpdate, request: Request, a: Actor = A):
        request.app.state.records.module_write(
            a, key, form.version, form.title, form.body
        )
        return {"ok": True}

    @api.get("/v1/modules/{key}/conversation")
    def thread(
        key: str, scope: Literal["private", "shared"], request: Request, a: Actor = A
    ):
        s = request.app.state
        with s.db.connection() as c:
            c.execute("BEGIN")
            record = s.records.module(c, a, key)
            drafts = [
                d
                for d in s.records.drafts(c, a)
                if d.get("target_id") == key and d["scope"] == scope
            ]
            return {
                "record": record,
                "scope": scope,
                "messages": s.chat.private_history(c, a, key, scope),
                "drafts": drafts,
            }

    @api.post("/v1/modules/{key}/conversation")
    def continue_thread(key: str, form: ModuleMessage, request: Request, a: Actor = A):
        request.app.state.chat.send(
            a,
            form.request_id,
            form.scope,
            text_value(form.text, 2000),
            key,
            form.version,
        )
        return {"ok": True}

    return api


app = create_app()
