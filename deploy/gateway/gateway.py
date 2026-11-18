"""Single-model, budgeted OpenAI-compatible connection for the couple Demo."""

import hmac
import json
import logging
import os
import sqlite3
from contextlib import asynccontextmanager, closing
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from starlette.background import BackgroundTask
from starlette.concurrency import run_in_threadpool

if __package__:
    from . import app_tools as tool_protocol
else:
    import app_tools as tool_protocol

MODEL = "deepseek-flash"
ENDPOINT = "https://api.deepseek.com/chat/completions"
MAX_BODY_BYTES = 16_384
BEIJING_TIME = timezone(timedelta(hours=8))
log = logging.getLogger("uvicorn.error")


@dataclass(frozen=True)
class Settings:
    gateway_token: str
    api_key: str
    database: Path
    daily_requests: int = 30
    output_tokens: int = 1024
    # Unbounded server-tool protocol is exercised only with injected test transports.
    synthetic_native_tools: bool = False

    @classmethod
    def from_env(cls):
        enabled = os.environ.get("DEEPSEEK_ENABLED", "false").lower()
        if enabled not in {"true", "false"}:
            raise ValueError("DEEPSEEK_ENABLED must be true or false")
        key = (
            os.environ.get("DEEPSEEK_API_KEY", "").strip() if enabled == "true" else ""
        )
        if enabled == "true" and not key:
            raise ValueError("Set DEEPSEEK_API_KEY before enabling DeepSeek")
        return cls(
            os.environ["DEMO_GATEWAY_TOKEN"],
            key,
            Path(os.environ["DEMO_BUDGET_DB"]),
            int(os.environ.get("DEMO_DAILY_REQUESTS", "30")),
            int(os.environ.get("DEMO_MAX_OUTPUT_TOKENS", "1024")),
        )

    def __post_init__(self):
        if len(self.gateway_token) < 32 or not self.gateway_token.isascii():
            raise ValueError(
                "Use a random ASCII DEMO_GATEWAY_TOKEN of at least 32 characters"
            )
        if not 1 <= self.daily_requests <= 30 or not 1 <= self.output_tokens <= 1024:
            raise ValueError("Daily request limit must be 1–30 and output limit 1–1024")


def reserve_request(settings: Settings, day: str, count: int = 1) -> int | None:
    if not 1 <= count <= settings.daily_requests:
        return None
    with closing(sqlite3.connect(settings.database, timeout=2)) as db, db:
        row = db.execute(
            """
            INSERT INTO daily_budget(day, used) VALUES (?, ?)
            ON CONFLICT(day) DO UPDATE SET used = used + excluded.used WHERE used + excluded.used <= ?
            RETURNING used
            """,
            (day, count, settings.daily_requests),
        ).fetchone()
        return row[0] if row else None


def error(status: int, message: str, code: str):
    return JSONResponse(
        {"error": {"message": message, "code": code}}, status_code=status
    )


async def request_payload(request: Request, output_limit: int):
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > MAX_BODY_BYTES:
            return error(413, "对话内容过长，请开始新对话或缩短输入。", "input_limit")
        body.extend(chunk)

    try:
        data = json.loads(body)
    except (ValueError, RecursionError):
        return error(400, "请求格式有误。", "invalid_json")
    if not isinstance(data, dict) or data.get("model") != MODEL:
        return error(400, "请选择 AI（DeepSeek）。", "unknown_model")

    messages = data.get("messages")
    limit = data.get("max_tokens")
    stream = data.get("stream", False)
    if (
        not isinstance(messages, list)
        or not messages
        or not all(
            isinstance(message, dict)
            and message.get("role") in ("system", "user", "assistant")
            and isinstance(message.get("content"), str)
            for message in messages
        )
        or (limit is not None and (type(limit) is not int or limit < 1))
        or type(stream) is not bool
    ):
        return error(400, "当前支持文本对话，请检查消息和输出选项。", "invalid_request")

    payload = {
        "model": MODEL,
        "messages": [
            {"role": message["role"], "content": message["content"]}
            for message in messages
        ],
        "max_tokens": min(output_limit, limit or output_limit),
        "thinking": {"type": "disabled"},
        "safety_check": {"level": "high"},
        "stream": stream,
    }
    if stream:
        payload["stream_options"] = {"include_usage": True}
    return payload


def log_usage(data, settings=None):
    usage = data.get("usage") if isinstance(data, dict) else None
    if isinstance(usage, dict):
        counts = [usage.get(key) for key in ("prompt_tokens", "completion_tokens")]
        if all(type(count) is int and count >= 0 for count in counts):
            if settings:
                tool_protocol.record(
                    settings,
                    "chat",
                    "model_tokens",
                    counts[1],
                    tool_protocol.valid_usage(usage),
                )
            log.warning("DeepSeek usage prompt_tokens=%d completion_tokens=%d", *counts)
            return counts[1]
    return None


async def stream_reply(upstream: httpx.Response, settings, limit):
    """Safety can reject the whole answer after all text deltas have arrived."""
    lines = []
    size = 0
    charged = False
    refused = False
    final_reason = None
    try:
        async for line in upstream.aiter_lines():
            size += len(line.encode()) + 1
            if size > 2 * 1024 * 1024:
                raise ValueError("Stream limit")
            if line == "data: [DONE]":
                if refused or not charged or final_reason != "stop":
                    raise ValueError("Incomplete or filtered response")
                for chunk in lines:
                    yield chunk
                yield line + "\n\n"
                return
            if line.startswith("data: "):
                data = json.loads(line[6:])
                if not isinstance(data, dict) or "error" in data:
                    raise ValueError("Provider error")
                refused = refused or any(
                    row.get("finish_reason") == "content_filter"
                    for row in data.get("choices", [])
                )
                for row in data.get("choices", []):
                    if row.get("finish_reason"):
                        final_reason = row["finish_reason"]
                if data.get("usage") and not charged:
                    count = log_usage(data, settings)
                    charged = count is not None
                    if charged and count > limit:
                        raise ValueError("Provider exceeded output cap")
            lines.append(line + "\n")
        raise ValueError("Stream ended without completion")
    except (httpx.HTTPError, ValueError, RecursionError) as exc:
        if not charged:
            tool_protocol.record(settings, "chat", "unsettled", None)
        log.warning("DeepSeek stream failed: %s", type(exc).__name__)
        failure = {"error": {"message": "回复中断或未通过安全审核。"}}
        yield f"data: {json.dumps(failure, ensure_ascii=False)}\n\ndata: [DONE]\n\n"
    finally:
        await upstream.aclose()


def create_app(
    settings: Settings | None = None, transport: httpx.AsyncBaseTransport | None = None
):
    settings = settings or Settings.from_env()
    if settings.synthetic_native_tools and not isinstance(
        transport, httpx.MockTransport
    ):
        raise ValueError(
            "Native multistep tools require a synthetic provider transport"
        )

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        with closing(sqlite3.connect(settings.database)) as db, db:
            db.execute(
                "CREATE TABLE IF NOT EXISTS daily_budget (day TEXT PRIMARY KEY, used INTEGER NOT NULL)"
            )
        async with httpx.AsyncClient(
            transport=transport, timeout=httpx.Timeout(45, connect=8), trust_env=False
        ) as client:
            app.state.client = client
            yield

    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
    expected_auth = f"Bearer {settings.gateway_token}".encode()

    def authorized(request: Request):
        return hmac.compare_digest(
            request.headers.get("authorization", "").encode(), expected_auth
        )

    @app.get("/health")
    async def health():
        return {
            "ok": True,
            "app_tools_revision": 1,
            "upstream_enabled": bool(settings.api_key),
            "native_multistep": settings.synthetic_native_tools,
            "bounded_web": True,
        }

    @app.get("/v1/models")
    async def models(request: Request):
        if not authorized(request):
            return error(401, "访问失败。", "unauthorized")
        return {
            "object": "list",
            "data": [
                {"id": MODEL, "object": "model", "name": "AI", "owned_by": "DeepSeek"}
            ],
        }

    @app.post("/v1/chat/completions")
    async def complete(request: Request):
        if not authorized(request):
            return error(401, "访问失败。", "unauthorized")
        if not settings.api_key:
            return error(
                503, "DeepSeek 暂时不可用，尚未启用真实模型。", "upstream_disabled"
            )
        payload = await request_payload(request, settings.output_tokens)
        if isinstance(payload, JSONResponse):
            return payload

        try:
            day = datetime.now(BEIJING_TIME).date().isoformat()
            used = await run_in_threadpool(reserve_request, settings, day)
        except sqlite3.Error as exc:
            log.error("Could not reserve DeepSeek budget: %s", type(exc).__name__)
            return error(503, "用量检查暂时不可用，请稍后重试。", "budget_unavailable")
        if used is None:
            return error(429, "今日 AI 调用已达上限，北京时间零点恢复。", "daily_limit")

        log.warning(
            "DeepSeek request reserved daily_used=%d output_limit=%d",
            used,
            payload["max_tokens"],
        )
        client = request.app.state.client
        try:
            upstream = await client.send(
                client.build_request(
                    "POST",
                    ENDPOINT,
                    headers={"Authorization": f"Bearer {settings.api_key}"},
                    json=payload,
                ),
                stream=True,
            )
            if upstream.status_code != 200:
                try:
                    await tool_protocol.read_response(upstream, 4096)
                except tool_protocol.Problem as exc:
                    tool_protocol.record(settings, "chat", "unsettled", None)
                    return error(exc.status, "供应端未完成请求，请核对用量。", exc.code)
                finally:
                    await upstream.aclose()
            if payload["stream"]:
                if not upstream.headers.get("content-type", "").startswith(
                    "text/event-stream"
                ):
                    await upstream.aclose()
                    return error(
                        502, "DeepSeek 返回格式异常，请稍后重试。", "upstream_format"
                    )
                return StreamingResponse(
                    stream_reply(upstream, settings, payload["max_tokens"]),
                    media_type="text/event-stream",
                    background=BackgroundTask(upstream.aclose),
                )
            try:
                data = json.loads(
                    await tool_protocol.read_response(upstream, 2 * 1024 * 1024)
                )
            finally:
                await upstream.aclose()
            if not isinstance(data, dict) or not data.get("choices"):
                raise ValueError("Unrecognized DeepSeek completion")
            count = log_usage(data, settings)
            if any(
                choice.get("finish_reason") == "content_filter"
                for choice in data["choices"]
            ):
                return error(
                    422, "模型安全审核未通过，此次未写入业务记录。", "content_filter"
                )
            if count is None:
                raise ValueError("Missing provider usage")
            if count > payload["max_tokens"] or any(
                choice.get("finish_reason") != "stop" for choice in data["choices"]
            ):
                return error(
                    502, "回复超限或已截断，业务动作未完成。", "tool_incomplete"
                )
            return data
        except tool_protocol.Problem as exc:
            tool_protocol.record(settings, "chat", "unsettled", None)
            return error(exc.status, "模型回复未完整返回。", exc.code)
        except (httpx.HTTPError, ValueError, RecursionError) as exc:
            tool_protocol.record(settings, "chat", "unsettled", None)
            log.warning("DeepSeek request failed: %s", type(exc).__name__)
            return error(502, "DeepSeek 暂时不可用，请稍后重试。", "upstream_failure")

    tool_protocol.register(app, settings, authorized, reserve_request)
    return app
