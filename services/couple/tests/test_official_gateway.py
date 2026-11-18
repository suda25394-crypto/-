"""Verify the private gateway envelope, common quota and final safety verdict without network."""

from contextlib import closing
from pathlib import Path
import json
import sqlite3
from tempfile import TemporaryDirectory
import unittest

import httpx
from fastapi.testclient import TestClient

from deploy.gateway.gateway import Settings, create_app
from ..upstream import Upstream, UpstreamConfig
from .official_fixture import Provider


class GatewayAppTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(self.enterContext(TemporaryDirectory()))
        self.model = Provider()
        self.requests = []
        self.stream = False
        self.token = "synthetic-internal-gateway-secret-00001"
        self.settings = Settings(
            self.token, "synthetic-official-fixture-only", self.tmp / "ledger", 2, 128
        )
        self.gw = self.enterContext(
            TestClient(create_app(self.settings, httpx.MockTransport(self.route)))
        )
        self.headers = {"Authorization": "Bearer " + self.token}

    def route(self, req):
        self.requests.append(req)
        if req.url.path == "/chat/completions":
            if self.stream:
                frames = [
                    '{"choices":[{"delta":{"content":"withheld-fragment"}}]}',
                    '{"choices":[{"finish_reason":"content_filter"}]}',
                    '{"choices":[],"usage":{"prompt_tokens":17,"completion_tokens":5}}',
                    "[DONE]",
                ]
                return httpx.Response(
                    200,
                    content="".join("data: " + v + "\n\n" for v in frames).encode(),
                    headers={"content-type": "text/event-stream"},
                )
            return httpx.Response(
                200,
                json={
                    "choices": [
                        {"message": {"content": "测试"}, "finish_reason": "stop"}
                    ],
                    "usage": {"prompt_tokens": 17, "completion_tokens": 5},
                },
            )
        return self.model(req)

    def legacy(self):
        return self.gw.post(
            "/v1/chat/completions",
            headers=self.headers,
            json={
                "model": "deepseek-flash",
                "messages": [{"role": "user", "content": "fixture"}],
                "max_tokens": 5000,
                "stream": self.stream,
            },
        )

    def test_lower_common_quota_and_meter(self):
        self.assertEqual(self.gw.get("/health").json()["app_tools_revision"], 1)
        self.assertEqual(self.legacy().status_code, 200)
        raw = json.loads(self.requests[0].content)
        self.assertEqual(raw["max_tokens"], 128)
        self.assertEqual(raw["safety_check"]["level"], "high")
        ok = self.gw.post(
            "/v1/couple-tools/search",
            headers=self.headers,
            json={"text": "合成公开活动"},
        )
        self.assertEqual(ok.status_code, 200, ok.text)
        self.assertEqual(self.legacy().status_code, 429)
        self.assertEqual(len(self.requests), 2)
        with closing(sqlite3.connect(self.settings.database)) as c:
            self.assertEqual(
                c.execute("select used from daily_budget").fetchone()[0], 2
            )
            meters = c.execute(
                "select operation,unit,quantity,usage from app_tool_meter order by rowid"
            ).fetchall()
        self.assertEqual(meters[0][:3], ("chat", "model_tokens", 5))
        self.assertEqual(json.loads(meters[0][3])["prompt_tokens"], 17)
        self.assertEqual(meters[1][:3], ("search", "requests", 1))

    def test_final_refusal_hides_partial_text(self):
        self.stream = True
        res = self.legacy()
        self.assertEqual(res.status_code, 200)
        self.assertNotIn("withheld-fragment", res.text)
        self.assertIn("error", res.text)

    def test_total_reported_output_including_safety_must_fit_before_release(self):
        plain = self.gw.post(
            "/v1/chat/completions",
            headers=self.headers,
            json={
                "model": "deepseek-flash",
                "messages": [{"role": "user", "content": "fixture"}],
                "max_tokens": 2,
            },
        )
        self.assertEqual(plain.status_code, 502)
        self.assertEqual(plain.json()["error"]["code"], "tool_incomplete")
        tool = self.gw.post(
            "/v1/couple-tools/title",
            headers=self.headers,
            json={"text": "synthetic", "output_limit": 2},
        )
        self.assertEqual(tool.status_code, 502)
        self.assertEqual(tool.json()["error"]["code"], "tool_incomplete")
        with closing(sqlite3.connect(self.settings.database)) as c:
            rows = c.execute(
                "SELECT operation,quantity FROM app_tool_meter ORDER BY rowid"
            ).fetchall()
        self.assertEqual(rows, [("chat", 5), ("title", 7)])

    def test_product_to_gateway_uses_only_internal_credentials(self):
        requests = []

        def product_wire(req):
            requests.append(req)
            if req.url.host == "web.test":
                return httpx.Response(200, json={"data": [{"id": "deepseek-flash"}]})
            response = self.gw.post(
                req.url.path,
                headers={"Authorization": req.headers["authorization"]},
                json=json.loads(req.content),
            )
            return httpx.Response(response.status_code, json=response.json())

        cfg = UpstreamConfig(
            "http://web.test",
            "http://gw.test",
            "synthetic-pair",
            frozenset({"alice", "bob"}),
            self.token,
            str(self.tmp / "product.sqlite"),
        )
        up = Upstream(cfg, httpx.MockTransport(product_wire))
        result = up.official_tool("synthetic-user-session", "web", {"text": "公开电影"})
        self.assertTrue(result["sources"])
        self.assertEqual(
            requests[0].headers["authorization"], "Bearer synthetic-user-session"
        )
        self.assertEqual(requests[1].headers["authorization"], "Bearer " + self.token)
        self.assertEqual(self.requests[-1].url.host, "api.deepseek.com")
        self.assertNotIn(self.token, repr(self.requests[-1].headers.raw))
        self.assertEqual(json.loads(self.requests[-1].content)["max_tokens"], 128)
        self.assertNotIn("tools", json.loads(self.requests[-1].content))
        self.assertEqual(self.requests[-2].url.path, "/v1/tools/search")
        self.assertEqual(
            self.gw.post("/v1/couple-tools/web", json={"text": "X"}).status_code, 401
        )

    def test_two_stage_request_reserves_both_slots_before_spending(self):
        self.legacy()
        res = self.gw.post(
            "/v1/couple-tools/parse_text",
            headers=self.headers,
            json={
                "file": {
                    "name": "a.pdf",
                    "mime": "application/pdf",
                    "data_b64": "JVBERi0x",
                },
                "text": "提取",
            },
        )
        self.assertEqual(res.status_code, 429)
        self.assertEqual(res.json()["error"]["code"], "daily_limit")
        self.assertEqual([r.url.path for r in self.requests], ["/chat/completions"])

    def test_no_unbounded_generation_or_charge_in_production_mode(self):
        self.assertFalse(self.gw.get("/health").json()["native_multistep"])
        denied = self.gw.post(
            "/v1/couple-tools/image_search",
            headers=self.headers,
            json={"text": "公开活动"},
        )
        self.assertEqual(denied.status_code, 503)
        self.assertEqual(denied.json()["error"]["code"], "multistep_budget_blocked")
        self.assertEqual(self.requests, [])
        url = "https://example.com/festival"
        answer = self.gw.post(
            "/v1/couple-tools/read_url",
            headers=self.headers,
            json={"text": url, "output_limit": 80},
        )
        self.assertEqual(answer.status_code, 200, answer.text)
        self.assertEqual(answer.json()["sources"][0]["url"], url)
        self.assertEqual(
            [r.url.path for r in self.requests],
            ["/v1/tools/fetch", "/anthropic/v1/messages"],
        )
        query = json.loads(self.requests[-1].content)
        self.assertNotIn("tools", query)
        self.assertEqual(query["max_tokens"], 80)
        self.assertEqual(
            [m["unit"] for m in answer.json()["meter"]], ["requests", "model_tokens"]
        )
        self.assertEqual(self.legacy().status_code, 429)

    def test_bounded_deep_search_has_one_search_one_thinking_generation(self):
        response = self.gw.post(
            "/v1/couple-tools/deep_search",
            headers=self.headers,
            json={"text": "公开活动", "output_limit": 80},
        )
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["search_mode"], "single_lookup")
        self.assertEqual(
            [r.url.path for r in self.requests],
            ["/v1/tools/search", "/anthropic/v1/messages"],
        )
        wire = json.loads(self.requests[-1].content)
        self.assertEqual(wire["thinking"], {"type": "enabled"})
        self.assertNotIn("tools", wire)
        self.assertEqual(wire["max_tokens"], 80)

    def test_followup_reuses_public_content_without_another_search(self):
        cfg = Settings(
            self.token, "synthetic-provider-key", self.tmp / "more-ledger", 3, 100
        )
        gw = self.enterContext(
            TestClient(create_app(cfg, httpx.MockTransport(self.route)))
        )
        first = gw.post(
            "/v1/couple-tools/web", headers=self.headers, json={"text": "公开活动"}
        )
        self.assertEqual(first.status_code, 200, first.text)
        follow = gw.post(
            "/v1/couple-tools/web",
            headers=self.headers,
            json={"text": "这条来源的详情呢？", "history": first.json()["history"]},
        )
        self.assertEqual(follow.status_code, 200, follow.text)
        self.assertEqual(
            [r.url.path for r in self.requests],
            ["/v1/tools/search", "/anthropic/v1/messages", "/anthropic/v1/messages"],
        )
        self.assertEqual(follow.json()["search_mode"], "same_source")
        self.assertIn(
            "公开节目信息",
            json.loads(self.requests[-1].content)["messages"][0]["content"],
        )
