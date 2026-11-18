"""Offline provider fixture for the optional native Open WebUI contract smoke."""

import json
import httpx
from gateway import Settings, create_app


def factory():
    settings = Settings.from_env()
    if settings.api_key != "local-fixture-only":
        raise RuntimeError("Refusing a real provider key in a local smoke test")

    def fake(request):
        body = json.loads(request.content)
        assert (
            body["model"] == "deepseek-flash"
            and not body["stream"]
            and body["max_tokens"] <= 1024
        )
        data = json.loads(body["messages"][1]["content"])
        quiet = any(
            m["text"] == "不喜欢人多" for m in data["authorized_context"]["memories"]
        )
        shared = data["scope"] == "shared"
        answer = {
            "reply": "安静场所" if quiet else "合成回复",
            "items": [
                {"module": "date", "title": "周六见面", "body": "预算200元"},
                {
                    "module": "calendar",
                    "title": "错峰时间" if quiet else "见面时间",
                    "body": "周六",
                },
            ]
            if shared
            else [],
            "memories": [] if shared else ["不喜欢人多"],
        }
        return httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "message": {"content": json.dumps(answer, ensure_ascii=False)},
                        "finish_reason": "stop",
                    }
                ],
                "usage": {"prompt_tokens": 11, "completion_tokens": 17},
            },
        )

    return create_app(settings, httpx.MockTransport(fake))
