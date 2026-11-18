"""Synthetic official API wire responses used only in the isolated fixture application."""

import base64
import io
import json
import wave
from pathlib import Path

import httpx
from fastapi.testclient import TestClient

from deploy.gateway.gateway import Settings, create_app
from ..upstream import UpstreamError

POSTER_TITLE = "海边电影夜"
POSTER_QUOTE = "2026-12-05 18:30 · 东门广场"
POSTER = Path(__file__).parent / "assets" / "winter-screening.png"


def wav():
    out = io.BytesIO()
    with wave.open(out, "wb") as f:
        f.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        f.writeframes(b"\0" * 3200)
    return out.getvalue()


class Provider:
    def __init__(self):
        self.requests = []
        self.stop = "end_turn"
        self.broken = False
        self.input_blocked = False
        self.no_pages = False
        self.refusal = False
        self.history_block = {
            "type": "web_search_tool_result",
            "tool_use_id": "synthetic-use",
            "kind": "search",
            "content": [
                {
                    "type": "web_search_result",
                    "title": "合成来源",
                    "url": "https://example.com/festival",
                    "encrypted_content": "synthetic-signature-123",
                }
            ],
        }

    def __call__(self, request):
        self.requests.append(request)
        path = request.url.path
        if self.input_blocked:
            return httpx.Response(
                400, json={"error": {"message": "Content Exists Risk"}}
            )
        if path == "/files":
            metadata = {"id": "file-api-synthetic-1", "expires_at": 9999999999}
            if not self.no_pages:
                metadata["page_count"] = 2
            return httpx.Response(200, json=metadata)
        if path.startswith("/files/file-api-"):
            return httpx.Response(200, json={"deleted": True})
        if path.endswith("/search"):
            return httpx.Response(
                200,
                json={
                    "results": [
                        {
                            "title": "合成来源",
                            "url": "https://example.com/festival",
                            "snippet": "公开节目信息",
                        }
                    ]
                },
            )
        if path.endswith("/fetch"):
            return httpx.Response(
                200, json={"title": "合成来源", "content": "公开节目信息"}
            )
        if path.endswith("/ocr"):
            return httpx.Response(
                200,
                json={
                    "page_count": 1,
                    "pages": [
                        {"index": 0, "text": POSTER_QUOTE, "finish_reason": "stop"}
                    ],
                },
            )
        if path.endswith("/asr"):
            return httpx.Response(
                200, json={"duration_ms": 3200, "text": "转写示例，发送前由本人修订。"}
            )
        if path.endswith("/tts"):
            return httpx.Response(
                200, content=wav(), headers={"content-type": "audio/wav"}
            )
        assert path == "/anthropic/v1/messages", path
        payload = json.loads(request.content)
        blocks = []
        text = "【合成工具回执】已读取。"
        if "tools" in payload:
            blocks.extend(
                [
                    {
                        "type": "server_tool_use",
                        "id": "synthetic-use",
                        "name": payload["tools"][0]["name"],
                        "input": {"queries": ["合成活动"]},
                    },
                    self.history_block,
                ]
            )
            text = "【合成回执】参考公开网页。"
        if "evidence" in payload.get("system", ""):
            img = payload["messages"][-1]["content"][0]["source"]["data"]
            if base64.b64decode(img) != POSTER.read_bytes():
                text = json.dumps(
                    {
                        "title": "待核对的海报",
                        "body": "合成上游不识别这张图。",
                        "evidence": "请逐项核对原图",
                    }
                )
            else:
                text = json.dumps(
                    {
                        "title": POSTER_TITLE,
                        "body": POSTER_QUOTE,
                        "evidence": POSTER_QUOTE,
                    },
                    ensure_ascii=False,
                )
        events = [
            {"type": "message_start", "message": {"role": "assistant", "content": []}}
        ]
        for i, block in enumerate(blocks):
            events.extend(
                [
                    {"type": "content_block_start", "index": i, "content_block": block},
                    {"type": "content_block_stop", "index": i},
                ]
            )
        i = len(blocks)
        events += [
            {
                "type": "content_block_start",
                "index": i,
                "content_block": {"type": "text", "text": ""},
            },
            {
                "type": "content_block_delta",
                "index": i,
                "delta": {"type": "text_delta", "text": text},
            },
            {"type": "content_block_stop", "index": i},
            {
                "type": "message_delta",
                "delta": {
                    "stop_reason": "refusal" if self.refusal else self.stop,
                    **({"title": "合成标题"} if "title" in payload else {}),
                },
                "usage": {
                    "input_tokens": 18,
                    "output_tokens": 7,
                    "server_tool_use": {"tool_search": int(bool(blocks))},
                },
            },
            {"type": "message_stop"},
        ]
        if self.broken:
            events.pop()
        data = "".join(
            "data: " + json.dumps(row, ensure_ascii=False) + "\n\n" for row in events
        )
        return httpx.Response(
            200, content=data.encode(), headers={"content-type": "text/event-stream"}
        )


def through_gateway(folder, provider, kind, payload, daily=30):
    token = "synthetic-internal-token-only-for-tests"
    settings = Settings(
        token,
        "synthetic-provider-key",
        Path(folder) / "synthetic-gateway.sqlite",
        daily,
        1024,
        synthetic_native_tools=True,
    )
    app = create_app(settings, httpx.MockTransport(provider))
    with TestClient(app) as client:
        res = client.post(
            "/v1/couple-tools/" + kind,
            headers={"Authorization": "Bearer " + token},
            json=payload,
        )
    data = res.json()
    if not res.is_success:
        raise UpstreamError(
            data["error"]["code"], "合成网关未返回完整结果。", res.status_code
        )
    return data
