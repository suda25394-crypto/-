"""HTTP contract and failure tests without network access or paid model calls."""

import json
import tempfile
import unittest
from pathlib import Path

import httpx

from services.couple.upstream import Upstream, UpstreamConfig, UpstreamError


class UpstreamTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.cfg = UpstreamConfig(
            "http://webui.test",
            "http://gateway.test",
            "pair",
            frozenset({"a", "b"}),
            "x" * 32,
            str(Path(self.tmp.name) / "storage.sqlite"),
        )
        self.sent = []
        self.thread = []
        self.writes = 0
        self.fail_after_commit = False
        self.members = ["a", "b"]
        self.enabled = True
        self.model_code = None
        self.grant = True
        self.last_model = None
        self.adapter = Upstream(self.cfg, httpx.MockTransport(self.route))

    def route(self, req):
        path, method = req.url.path, req.method
        self.assertNotIn("cookie", req.headers)
        if req.url.host == "gateway.test":
            self.assertEqual(req.headers["Authorization"], "Bearer " + "x" * 32)
            self.assertEqual(path, "/v1/chat/completions")
            self.last_model = json.loads(req.content)
            if self.model_code:
                return httpx.Response(
                    429 if self.model_code == "daily_limit" else 503,
                    json={"error": {"code": self.model_code}},
                )
            result = {"reply": "已整理", "items": [], "memories": ["候选"]}
            return httpx.Response(
                200,
                json={
                    "choices": [{"message": {"content": json.dumps(result)}}],
                    "usage": {"prompt_tokens": 8, "completion_tokens": 4},
                },
            )
        if path == "/api/v1/auths/signin":
            return httpx.Response(
                200,
                json={"token": "a", "id": "a", "name": "A", "role": "user"},
                headers={"Set-Cookie": "token=a"},
            )
        owner = req.headers["Authorization"].removeprefix("Bearer ")
        if path == "/api/v1/auths/":
            return httpx.Response(
                200, json={"id": owner, "name": owner.upper(), "role": "user"}
            )
        if path == "/api/v1/channels/pair":
            return httpx.Response(
                200,
                json={
                    "id": "pair",
                    "type": "group",
                    "is_private": True,
                    "user_ids": self.members,
                },
            )
        if path == "/api/models":
            return httpx.Response(
                200, json={"data": [{"id": "deepseek-flash"}] if self.grant else []}
            )
        if path.endswith("/messages/post") and method == "POST":
            self.writes += 1
            body = json.loads(req.content)
            row = {
                **body,
                "id": str(self.writes),
                "user_id": owner,
                "channel_id": "pair",
                "created_at": self.writes * 10**9,
            }
            self.sent.append(row)
            if self.fail_after_commit:
                self.fail_after_commit = False
                raise httpx.ReadTimeout("fixture")
            return httpx.Response(200, json=row)
        if path.endswith("/messages"):
            return httpx.Response(
                200, json=[{**m, "data": bool(m["data"])} for m in reversed(self.sent)]
            )
        if path.endswith("/thread"):
            return httpx.Response(200, json=self.thread)
        if path.endswith("/data"):
            index = path.split("/")[-2]
            return httpx.Response(
                200, json=next(m["data"] for m in self.sent if m["id"] == index)
            )
        raise AssertionError(path)

    def code(self, expected, method, *args):
        with self.assertRaises(UpstreamError) as cm:
            method(*args)
        self.assertEqual(cm.exception.code, expected)

    def test_disjoint_sessions_and_exact_members(self):
        self.assertEqual(self.adapter.login("synthetic", "password")["token"], "a")
        self.adapter.check_member("a", "a")
        self.adapter.check_member("b", "b")
        self.code("channel_forbidden", self.adapter.check_member, "a", "b")
        self.members.append("c")
        self.code("channel_forbidden", self.adapter.check_member, "a", "a")
        self.code("channel_forbidden", self.adapter.channel_post, "a", "secret", "r")
        self.assertFalse(self.sent)

    def test_channel_replay_authorship_and_native_mention(self):
        self.adapter.channel_post("a", "hi <@M:deepseek-flash|AI>", "user-1")
        self.assertNotIn("<@M:", self.sent[0]["content"])
        self.adapter.channel_post("a", "回复", "ai-1", "assistant")
        self.adapter.channel_post("a", "回复", "ai-1", "assistant")
        self.adapter.channel_post("b", "AI · 冒充", "u2")
        self.assertEqual(
            [m["role"] for m in self.adapter.channel_messages("b")],
            ["user", "assistant", "user"],
        )
        self.code(
            "request_conflict",
            self.adapter.channel_post,
            "a",
            "changed",
            "ai-1",
            "assistant",
        )
        self.sent[1]["content"] += "tamper"
        self.assertEqual(self.adapter.channel_messages("b")[1]["role"], "user")

    def test_native_threads_are_bound_to_root_channel_and_authenticated_author(self):
        self.adapter.channel_post("a", "原生频道测试", "native-root")
        root = self.sent[0]
        root["reply_count"] = 3
        self.thread = [
            {
                **root,
                "parent_id": "1",
                "id": "model",
                "meta": {"model_id": "deepseek-flash"},
                "content": "原生回复",
            },
            {**root, "parent_id": "other", "id": "foreign-thread", "content": "不可见"},
            {
                **root,
                "parent_id": "1",
                "channel_id": "other",
                "id": "foreign-channel",
                "content": "不可见",
            },
        ]
        rows = self.adapter.channel_messages("b")
        self.assertEqual(
            [(r["role"], r["text"]) for r in rows],
            [("user", "原生频道测试"), ("assistant", "原生回复")],
        )

    def test_unknown_delivery_reconciles_without_resend_even_after_restart(self):
        self.fail_after_commit = True
        self.code(
            "delivery_unknown", self.adapter.channel_post, "a", "共同消息", "lost"
        )
        restarted = Upstream(self.cfg, httpx.MockTransport(self.route))
        self.assertEqual(restarted.channel_post("a", "共同消息", "lost")["id"], "1")
        self.assertEqual(self.writes, 1)
        self.fail_after_commit = True
        self.code(
            "delivery_unknown",
            restarted.channel_post,
            "a",
            "unknown",
            "lost-never-found",
        )
        self.sent.pop()
        self.code(
            "delivery_unknown",
            restarted.channel_post,
            "a",
            "unknown",
            "lost-never-found",
        )
        self.assertEqual(self.writes, 2)

    def test_model_grant_caps_errors_and_returned_usage(self):
        self.grant = False
        self.code("model_access", self.adapter.complete, "a", "private", "ask", {})
        self.assertIsNone(self.last_model)
        self.grant = True
        resp = self.adapter.complete(
            "a", "shared", "ask", {"memories": [{"text": "m" * 2000}] * 18}
        )
        self.assertEqual(self.last_model["max_tokens"], 1024)
        self.assertFalse(self.last_model["stream"])
        self.assertEqual(resp["usage"], {"prompt_tokens": 8, "completion_tokens": 4})
        self.assertEqual(resp["memories"], [])
        self.model_code = "upstream_disabled"
        self.code("upstream_disabled", self.adapter.complete, "a", "private", "ask", {})
        self.model_code = "daily_limit"
        self.code("daily_limit", self.adapter.complete, "a", "private", "ask", {})


if __name__ == "__main__":
    unittest.main()
