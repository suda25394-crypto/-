"""D-44/D-48 acceptance at product routes and at the actual Gateway request boundary."""

import json
import tempfile
import unittest
from pathlib import Path

import httpx
from fastapi.testclient import TestClient

from ..database import encode
from ..upstream import Upstream, UpstreamConfig
from .fixture import fixture_app


class RouteTests(unittest.TestCase):
    def setUp(self):
        root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.app, self.model = fixture_app(root)
        self.http = self.enterContext(TestClient(self.app))
        self.calls = []
        self.force_actions = False
        synthetic = self.model.complete

        def capture(req):
            if req.url.host == "web.test":
                return httpx.Response(200, json={"data": [{"id": "deepseek-flash"}]})
            wire = json.loads(req.content)
            data = json.loads(wire["messages"][1]["content"])
            assert wire["max_tokens"] <= 1024
            self.calls.append((wire["messages"][0]["content"], data))
            # Synthetic provider uses exactly what the real Gateway would receive.
            raw = synthetic(
                self.actor_token,
                data["scope"],
                data["request"],
                data["authorized_context"],
            )
            usage = raw.pop("usage")
            if self.force_actions:
                raw["items"] = [
                    {"module": "memory", "title": "越权共享", "body": "私密求助"}
                ]
                raw["memories"] = ["未经本人确认的推断"]
            return httpx.Response(
                200,
                json={
                    "choices": [{"message": {"content": encode(raw)}}],
                    "usage": usage,
                },
            )

        self.adapter = Upstream(
            UpstreamConfig(
                "http://web.test",
                "http://gateway.test",
                "test",
                frozenset({"alice", "bob"}),
                "f" * 32,
                str(root / "wire.sqlite"),
            ),
            httpx.MockTransport(capture),
        )

        def model(token, scope, text, context):
            self.actor_token = token
            return self.adapter.complete(token, scope, text, context)

        self.model.complete = model
        self.seq = 0
        self.a, self.b = (self.login(k) for k in ("a", "b"))

    def login(self, owner):
        r = self.http.post(
            "/v1/login",
            json={"email": owner + "@example.test", "password": "fixture-only"},
        )
        r.raise_for_status()
        return {"Authorization": "Bearer " + r.json()["token"]}

    def call(self, actor, method, path, body=None, code=200):
        r = self.http.request(method, "/v1/" + path, headers=actor, json=body)
        self.assertEqual(r.status_code, code, r.text)
        return r.json()

    def state(self, a):
        return self.call(a, "GET", "state")

    def chat(self, scope, text, *, actor=None, record=None):
        self.seq += 1
        data = dict(scope=scope, text=text, request_id=f"route-case-{self.seq:04}")
        path = "messages"
        if record:
            path = f"modules/{record['id']}/conversation"
            data["version"] = record["version"]
        return self.call(actor or self.a, "POST", path, data)

    def plan(self, title):
        self.seq += 1
        self.call(
            self.a,
            "POST",
            "modules",
            dict(
                confirmed=True,
                request_id=f"manual-case-{self.seq:03}",
                module="date",
                title=title,
                body="周末上午约会",
            ),
        )
        return next(r for r in self.state(self.a)["modules"] if r["title"] == title)

    def test_three_entries_general_followup_then_authorized_plan(self):
        item = self.plan("周末共同计划")
        body = "把我们确认好的周末计划改成下午"
        required_prompt = (
            Path(__file__).resolve().parents[3] / "prompts/dp-relationship.zh-CN.md"
        ).read_text(encoding="utf-8")
        for scope, module in (("private", False), ("shared", False), ("private", True)):
            with self.subTest(scope=scope, module=module):
                prefix = "@DP " if scope == "shared" else ""
                target = item if module else None
                before = len(self.calls)
                self.force_actions = True
                self.chat(
                    scope,
                    prefix + "日语的「そうだ」和「ようだ」有什么区别",
                    record=target,
                )
                self.chat(
                    scope, prefix + "用刚才的句型给她写一句鼓励的话", record=target
                )
                first, second = self.calls[before : before + 2]
                for rules, msg in (first, second):
                    self.assertIn(required_prompt, rules)
                    ctx = msg["authorized_context"]
                    self.assertEqual(ctx["intent"], ["general"])
                    for k in (
                        "profiles",
                        "memories",
                        "modules",
                        "module_target",
                        "mandates",
                        "reflections",
                        "activity_experiences",
                    ):
                        self.assertFalse(ctx.get(k), k)
                    self.assertNotIn("周末上午约会", encode(ctx))
                self.assertTrue(
                    any(
                        r["role"] == "assistant" and "传闻" in r["text"]
                        for r in second[1]["authorized_context"]["conversation"]
                    )
                )
                self.assertFalse(self.state(self.a)["memories"])
                self.assertFalse(
                    [
                        r
                        for r in self.state(self.a)["drafts"]
                        if r["status"] == "pending"
                    ]
                )
                if module:
                    hist = self.call(
                        self.a,
                        "GET",
                        f"modules/{item['id']}/conversation?scope={scope}",
                    )["messages"]
                else:
                    hist = self.state(self.a)["messages"][scope]
                self.assertIn("応援しているよ", hist[-1]["text"])
                self.force_actions = False
                self.chat(scope, prefix + body, record=target)
                ctx = self.calls[-1][1]["authorized_context"]
                self.assertEqual(ctx["module_target"][0]["id"], item["id"])
                self.assertEqual(ctx["module_target"][0]["version"], item["version"])
                status = self.state(self.a)
                self.assertEqual(status["modules"][0]["version"], item["version"])
                draft = next(r for r in status["drafts"] if r["status"] == "pending")
                self.assertEqual(draft["target_id"], item["id"])
                edits = [dict(draft["items"][0], body="周末下午见面")]
                self.call(
                    self.a,
                    "POST",
                    "drafts/" + draft["id"] + "/confirm",
                    dict(version=1, items=edits),
                )
                self.call(
                    self.a,
                    "POST",
                    "drafts/" + draft["id"] + "/confirm",
                    dict(version=1, items=edits),
                )
                self.assertEqual(len(self.calls) - before, 3)
                updated = self.state(self.b)["modules"]
                self.assertEqual(len(updated), 1)
                self.assertEqual(
                    (updated[0]["id"], updated[0]["version"], updated[0]["body"]),
                    (item["id"], item["version"] + 1, "周末下午见面"),
                )
                item = updated[0]
        before = len(self.calls)
        self.chat("shared", "普通群聊：今晚见")
        self.assertEqual(len(self.calls), before)

    def test_general_information_never_reads_shared_records_even_in_guided_chat(self):
        shared_marker = "双方授权但本题无关的资料-18"
        plan = self.plan(shared_marker)
        self.call(
            self.b,
            "PUT",
            "profile",
            {
                "version": 0,
                "published": True,
                "data": {"life": {"avoid": shared_marker}, "communication": {}},
            },
        )
        self.chat("shared", "普通群聊 " + shared_marker, actor=self.b)
        self.call(self.a, "POST", "profile-mode/start", {"version": 0})
        self.force_actions = True
        examples = (
            "什么是旅行预算？",
            "解释数据库中的日程表",
            "推荐一首无关的歌",
            "What is a travel plan?",
            "Explain schedule management in operating systems.",
            "旅行プランとは何ですか？",
            "请用英语翻译『我喜欢独处』",
            "改成英文翻译练习",
        )
        for scope, module in (("private", None), ("shared", None), ("private", plan)):
            for question in examples:
                with self.subTest(scope=scope, module=bool(module), question=question):
                    self.chat(
                        scope,
                        ("@DP " if scope == "shared" else "") + question,
                        record=module,
                    )
                    ctx = self.calls[-1][1]["authorized_context"]
                    self.assertEqual(ctx["intent"], ["general"])
                    self.assertNotIn(shared_marker, encode(ctx))
                    for key in (
                        "modules",
                        "profiles",
                        "memories",
                        "module_target",
                        "profile_mode",
                        "history",
                        "feedback",
                    ):
                        self.assertFalse(ctx.get(key), key)
        self.assertFalse(self.state(self.a)["memories"])
        self.assertFalse(
            [d for d in self.state(self.a)["drafts"] if d["status"] == "pending"]
        )

    def test_relationship_prompt_and_private_safety_have_no_side_effects(self):
        self.force_actions = True
        self.call(self.a, "POST", "profile-mode/start", {"version": 0})
        marker = "绿伞-私人案例"
        for text, route, reply in (
            ("好消息，我拿到了实习录取", "relationship", "开心"),
            ("我刚才说重了，但这件事还是得谈", "relationship", "对不起"),
            ("这张截图能证明她是回避型吗？", "relationship", "无法判断"),
            ("我们有分歧，但我不想参加复盘", "relationship", "随时退出"),
            (marker + "，我喜欢独处，但我担心他会报复我", "safety", "安全"),
            ("我已经决定离开关系", "relationship", "决定由你"),
        ):
            self.chat("private", text)
            rules, wire = self.calls[-1]
            self.assertIn("不能给人判定依恋类型", rules)
            self.assertIn("不要通知伴侣", rules)
            self.assertIn("任何一方可以退出", rules)
            ctx = wire["authorized_context"]
            self.assertEqual(ctx["intent"], [route])
            self.assertFalse(ctx.get("profile_mode"))
            self.assertFalse(ctx.get("module_target"))
            self.assertIn(reply, self.state(self.a)["messages"]["private"][-1]["text"])
        self.assertFalse(self.state(self.a)["memories"])
        self.assertFalse(self.state(self.a)["drafts"])
        peer = self.state(self.b)
        for key in ("reflections", "drafts", "modules", "memories"):
            self.assertFalse(peer[key])
        self.assertFalse(peer["messages"]["shared"])
        self.assertNotIn(marker, encode(peer))
        self.chat("shared", "@DP 我想问问复盘", actor=self.b)
        self.assertNotIn(marker, encode(self.calls[-1][1]))
        with self.app.state.db.connection() as c:
            self.assertEqual(
                c.execute("SELECT count(*) FROM tool_turns").fetchone()[0], 0
            )

    def test_both_may_decline_leave_correct_and_independently_approve(self):
        def invite(key):
            return self.call(
                self.a, "POST", "reflections", dict(request_id=key, shared=True)
            )["id"]

        def act(who, key, action, version, text="", code=200):
            return self.call(
                who,
                "POST",
                "reflections/" + key,
                dict(action=action, version=version, text=text),
                code,
            )

        key = invite("invited-first")
        act(self.a, key, "propose", 1, "先写共同约定", 409)
        act(self.b, key, "leave", 1)
        self.assertFalse(self.state(self.a)["reflections"])
        key = invite("invited-second")
        act(self.b, key, "join", 1)
        act(self.b, key, "join", 1)
        act(self.a, key, "statement", 2, "我想有一会儿安静")
        act(self.b, key, "statement", 3, "我更在意什么时候再谈")
        self.chat("shared", "@DP 我们有分歧")
        refs = self.calls[-1][1]["authorized_context"]["reflections"]
        self.assertIn("想有一会儿安静", encode(refs))
        act(self.b, key, "leave", 4)
        self.chat("shared", "@DP 刚才的分歧呢")
        self.assertNotIn(
            "想有一会儿安静", encode(self.calls[-1][1]["authorized_context"])
        )
        self.assertFalse(self.state(self.a)["modules"])
        key = invite("invited-third")
        act(self.b, key, "join", 1)
        act(self.a, key, "statement", 2, "需要一点时间")
        act(self.a, key, "statement", 3, "是希望晚饭后再谈")
        act(self.b, key, "propose", 4, "晚饭后一起谈十分钟")
        act(self.a, key, "approve", 5)
        act(self.a, key, "approve", 5)
        self.assertFalse(self.state(self.a)["modules"])
        act(self.b, key, "propose", 6, "散步时再谈十分钟")
        self.assertFalse(
            any(r["approved"] for r in self.state(self.b)["reflections"][0]["members"])
        )
        act(self.b, key, "approve", 7)
        self.assertFalse(self.state(self.b)["modules"])
        act(self.a, key, "approve", 8)
        act(self.b, key, "approve", 7)
        records = self.state(self.b)["modules"]
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["body"], "散步时再谈十分钟")
        self.assertEqual(records, self.state(self.a)["modules"])
        self.assertEqual(len(self.calls), 2)
