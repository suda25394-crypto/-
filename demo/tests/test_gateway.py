import json
import sqlite3
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx
from contextlib import asynccontextmanager, closing

from gateway import ENDPOINT, MAX_BODY_BYTES, MODEL, Settings, create_app, reserve_request

TOKEN = "local-test-gateway-token-unrelated-to-production"
AUTH = {"Authorization": f"Bearer {TOKEN}"}
BODY = {"model": MODEL, "messages": [{"role": "user", "content": "测试消息"}]}


class GatewayTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.database = Path(folder.name) / "budget.sqlite3"
        self.requests = []

    @asynccontextmanager
    async def client(self, key="local-test-provider-key", daily=2, handler=None):
        def transport(request):
            self.requests.append(request)
            if handler:
                return handler(request)
            return httpx.Response(
                200,
                json={"choices": [{"message": {"content": "测试夹具"}}], "usage": {"prompt_tokens": 8, "completion_tokens": 2}},
            )

        settings = Settings(TOKEN, key, self.database, daily_requests=daily, output_tokens=100)
        app = create_app(settings, httpx.MockTransport(transport))
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://testserver") as client:
                yield client

    async def test_disabled_gateway_and_model_discovery(self):
        async with self.client(key="") as client:
            self.assertEqual((await client.get("/v1/models")).status_code, 401)
            self.assertEqual((await client.get("/v1/models", headers=AUTH)).json()["data"][0]["id"], MODEL)
            self.assertFalse((await client.get("/health")).json()["upstream_enabled"])
            response = await client.post("/v1/chat/completions", headers=AUTH, json=BODY)
            self.assertEqual(response.status_code, 503)
            self.assertEqual(response.json()["error"]["code"], "upstream_disabled")
        self.assertEqual(self.requests, [])

    async def test_invalid_model_text_and_oversize_are_rejected_before_charging(self):
        async with self.client(daily=1) as client:
            url = "/v1/chat/completions"
            self.assertEqual((await client.post(url, json=BODY)).status_code, 401)
            self.assertEqual((await client.post(url, headers=AUTH, content=b"{")).status_code, 400)
            self.assertEqual((await client.post(url, headers=AUTH, json={**BODY, "model": "wrong"})).status_code, 400)
            bad = {"role": "user", "content": [{"type": "image_url", "url": "https://example.invalid"}]}
            self.assertEqual((await client.post(url, headers=AUTH, json={**BODY, "messages": [bad]})).status_code, 400)
            self.assertEqual((await client.post(url, headers=AUTH, content=b" " * (MAX_BODY_BYTES + 1))).status_code, 413)
            self.assertEqual((await client.post(url, headers=AUTH, json=BODY)).status_code, 200)
        self.assertEqual(len(self.requests), 1)

    async def test_fixed_provider_output_cap_and_budget_survive_restart(self):
        async with self.client(daily=1) as client:
            body = {
                **BODY,
                "max_tokens": 50000,
                "thinking": {"type": "enabled"},
                "tools": [{"type": "web_search"}],
                "upstream_override": "https://example.invalid",
            }
            response = await client.post("/v1/chat/completions", headers=AUTH, json=body)
            self.assertEqual(response.status_code, 200)
        async with self.client(daily=1) as client:
            response = await client.post("/v1/chat/completions", headers=AUTH, json=BODY)
            self.assertEqual(response.status_code, 429)
        self.assertEqual(len(self.requests), 1)
        sent = self.requests[0]
        self.assertEqual(str(sent.url), ENDPOINT)
        self.assertEqual(sent.headers["Authorization"], "Bearer local-test-provider-key")
        self.assertEqual(json.loads(sent.content), {
            **BODY, "max_tokens": 100, "thinking": {"type": "disabled"}, "stream": False,
        })

    async def test_stream_preserves_sse_and_records_usage(self):
        events = (
            'data: {"choices":[{"delta":{"content":"测试夹具"}}]}\n\n'
            'data: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":4}}\n\n'
            'data: [DONE]\n\n'
        )
        async with self.client(handler=lambda _: httpx.Response(
            200, text=events, headers={"content-type": "text/event-stream"}
        )) as client:
            with self.assertLogs("uvicorn.error", level="WARNING") as captured:
                response = await client.post("/v1/chat/completions", headers=AUTH, json={**BODY, "stream": True})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.text, events)
        self.assertEqual(json.loads(self.requests[0].content)["stream_options"], {"include_usage": True})
        self.assertIn("prompt_tokens=5 completion_tokens=4", "\n".join(captured.output))

    async def test_incomplete_stream_reports_error(self):
        with self.assertLogs("uvicorn.error", level="WARNING"):
            async with self.client(handler=lambda _: httpx.Response(
                200, text='data: {"choices":[]}\n\n', headers={"content-type": "text/event-stream"}
            )) as client:
                response = await client.post("/v1/chat/completions", headers=AUTH, json={**BODY, "stream": True})
        self.assertIn("回复已中断", response.text)
        self.assertIn("data: [DONE]", response.text)

    async def test_provider_errors_are_generic_and_attempts_are_counted(self):
        def timeout(request):
            raise httpx.ReadTimeout("private content should never echo", request=request)

        for handler in (
            timeout,
            lambda _: httpx.Response(402, json={"error": "private content should never echo"}),
        ):
            async with self.client(handler=handler) as client:
                with self.assertLogs("uvicorn.error", level="WARNING") as captured:
                    response = await client.post("/v1/chat/completions", headers=AUTH, json=BODY)
            self.assertEqual(response.status_code, 502)
            self.assertNotIn("private content", response.text + "\n".join(captured.output))
        async with self.client() as client:
            self.assertEqual((await client.post("/v1/chat/completions", headers=AUTH, json=BODY)).status_code, 429)
        self.assertEqual(len(self.requests), 2)

    async def test_budget_reservation_atomic_and_reset_by_day(self):
        async with self.client():
            settings = Settings(TOKEN, "local-test-provider-key", self.database, daily_requests=3)
            with ThreadPoolExecutor(max_workers=8) as pool:
                results = list(pool.map(lambda _: reserve_request(settings, "2026-11-16"), range(16)))
            self.assertEqual(sorted(value for value in results if value is not None), [1, 2, 3])
            self.assertEqual(reserve_request(settings, "2026-11-17"), 1)

    async def test_database_failure_prevents_upstream_call(self):
        async with self.client() as client:
            with closing(sqlite3.connect(self.database)) as database, database:
                database.execute("DROP TABLE daily_budget")
            response = await client.post("/v1/chat/completions", headers=AUTH, json=BODY)
        self.assertEqual(response.status_code, 503)
        self.assertEqual(self.requests, [])
