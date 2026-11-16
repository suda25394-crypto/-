"""Offline transport for end-to-end tests of Open WebUI; excluded from the container."""

import json

import httpx

from gateway import Settings, create_app

REPLY = "OFFLINE TEST FIXTURE."


def fake_deepseek(request):
    payload = json.loads(request.content)
    assert payload["model"] == "deepseek-flash"
    assert payload["stream"] is True
    envelope = {"id": "fixture", "model": "deepseek-flash", "object": "chat.completion.chunk", "created": 1}
    events = (
        {**envelope, "choices": [{"index": 0, "delta": {"role": "assistant", "content": REPLY}, "finish_reason": None}]},
        {**envelope, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]},
        {"choices": [], "usage": {"prompt_tokens": 10, "completion_tokens": 4}},
    )
    body = "".join(f"data: {json.dumps(event)}\n\n" for event in events) + "data: [DONE]\n\n"
    return httpx.Response(200, text=body, headers={"content-type": "text/event-stream"})


def create_fixture_app():
    settings = Settings.from_env()
    if settings.api_key != "fixture-only":
        raise ValueError("Set DEEPSEEK_API_KEY=fixture-only for this offline test transport.")
    return create_app(settings, httpx.MockTransport(fake_deepseek))
