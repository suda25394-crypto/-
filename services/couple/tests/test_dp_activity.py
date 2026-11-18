"""D-43 acceptance through authenticated product HTTP and a synthetic upstream."""

import json
import unittest
from uuid import uuid4

from fastapi.testclient import TestClient
from . import test_product as product
from .fixture import fixture_app


class ActivityTests(unittest.TestCase):
    setUp = product.ProductTests.setUp
    login = product.ProductTests.login
    call = product.ProductTests.call
    state = product.ProductTests.state
    msg = product.ProductTests.msg

    def create_activity(self, title, body):
        self.call(
            "POST",
            "modules",
            self.a,
            {
                "request_id": uuid4().hex,
                "module": "date",
                "title": title,
                "body": body,
                "confirmed": True,
            },
        )
        return next(
            r["id"] for r in self.state(self.a)["modules"] if r["title"] == title
        )

    def item(self, actor, key):
        return next(r for r in self.state(actor)["activities"] if r["module_id"] == key)

    def write(
        self,
        actor,
        key,
        action,
        *,
        version=0,
        proposal=1,
        expected=200,
        method="PUT",
        **fields,
    ):
        return self.call(
            method,
            "modules/" + key + "/" + action,
            actor,
            {"version": version, "proposal_version": proposal, **fields},
            expected,
        )

    def suggest(self, actor, scope, text):
        self.msg(actor, scope, text, uuid4().hex)
        return self.source.contexts[-1][1]

    def test_separate_option_votes_and_idempotent_consensus(self):
        # Two ordinary channel posts followed by a deterministic model suggestion.
        original = self.source.complete

        def suggest_options(token, scope, text, context):
            result = original(token, scope, text, context)
            if "帮我们安排" in text:
                exists = {(m["owner"], m["text"]) for m in context["conversation"]}
                self.assertIn(("alice", "我想看展"), exists)
                self.assertIn(("bob", "我只想吃饭"), exists)
                result["items"] = [
                    {
                        "module": "date",
                        "title": "一起吃晚饭",
                        "body": "先在馆外会合吃饭",
                    },
                    {
                        "module": "date",
                        "title": "可选展览",
                        "body": "饭后可自行决定是否进馆",
                    },
                ]
            return result

        self.source.complete = suggest_options
        self.msg(self.a, "shared", "我想看展", uuid4().hex)
        self.msg(self.b, "shared", "我只想吃饭", uuid4().hex)
        self.suggest(self.b, "shared", "@AI 帮我们安排")
        draft = self.state(self.a)["drafts"][0]
        self.call(
            "POST",
            "drafts/" + draft["id"] + "/confirm",
            self.a,
            {"version": draft["version"]},
        )
        ids = {r["title"]: r["id"] for r in self.state(self.b)["modules"]}
        dinner, show = ids["一起吃晚饭"], ids["可选展览"]
        self.assertFalse(self.item(self.a, dinner)["agreed"])
        for mid in [dinner, show]:
            self.write(self.a, mid, "vote", choice="accept")
            self.write(self.a, mid, "vote", choice="accept")
            result = self.item(self.b, mid)
            self.assertFalse(result["agreed"])
            self.assertEqual(
                [(v["owner"], v["version"]) for v in result["votes"]],
                [("alice", 1), ("bob", 0)],
            )
        self.write(self.b, show, "vote", choice="pending", note="看当晚安排")
        self.write(self.b, show, "vote", version=1, choice="decline", note="我只想吃饭")
        self.write(self.b, dinner, "vote", choice="accept")
        self.assertTrue(self.item(self.a, dinner)["agreed"])
        self.assertFalse(self.item(self.a, show)["agreed"])
        self.write(self.a, show, "vote", choice="accept", owner="bob", expected=422)
        ctx = self.suggest(self.a, "shared", "@AI 周末想出去")
        decisions = {r["title"]: r for r in ctx["activity_decisions"]}
        self.assertTrue(decisions["一起吃晚饭"]["agreed"])
        self.assertFalse(decisions["可选展览"]["agreed"])
        self.assertEqual(
            next(
                v["choice"]
                for v in decisions["可选展览"]["votes"]
                if v["owner"] == "bob"
            ),
            "decline",
        )
        self.call(
            "PUT",
            "modules/" + dinner,
            self.a,
            {"version": 1, "title": "改为早餐", "body": "早上七点"},
        )
        self.write(self.b, dinner, "vote", choice="accept", proposal=1, expected=409)
        self.assertFalse(self.item(self.b, dinner)["agreed"])
        self.assertTrue(
            all(v["choice"] is None for v in self.item(self.b, dinner)["votes"])
        )

    def test_feedback_scope_correction_recall_and_withdrawal(self):
        key = self.create_activity("咖啡散步", "逛街后去喝咖啡")
        original = self.source.complete

        def recommend(token, scope, text, context):
            result = original(token, scope, text, context)
            for row in context["activity_experiences"]:
                if row["owner"] == "alice" and "书摊" in row["text"]:
                    result["reply"] = "【合成模型回执】Alice 上次喜欢逛书摊；可以再去。"
            return result

        self.source.complete = recommend
        review = "咖啡一般，路上的书摊倒很好逛"
        self.write(self.a, key, "review", text=review, scope="private", expected=409)
        for step in ("saved", "planned", "happened"):
            self.write(self.a, key, "steps/" + step, enabled=True)
            if step != "happened":
                self.assertNotIn("happened", self.item(self.a, key)["steps"])
        self.assertEqual(self.item(self.b, key)["steps"], {})
        self.write(self.a, key, "review", text=review, scope="private")
        self.write(self.a, key, "review", text=review, scope="private")
        self.assertEqual(self.item(self.a, key)["my_review_version"], 1)
        for actor, scope in [
            (self.b, "private"),
            (self.a, "shared"),
            (self.b, "shared"),
        ]:
            ctx = self.suggest(actor, scope, "@AI 推荐周末约会")
            self.assertNotIn("书摊", json.dumps(ctx, ensure_ascii=False))
        self.assertEqual(self.item(self.b, key)["reviews"], [])
        ctx = self.suggest(self.a, "private", "下次约会去哪？")
        evidence = ctx["activity_experiences"]
        self.assertEqual(
            [(v["module_id"], v["owner"], v["text"]) for v in evidence],
            [(key, "alice", review)],
        )
        self.assertIn(
            "Alice 上次喜欢逛书摊",
            self.state(self.a)["messages"]["private"][-1]["text"],
        )
        self.write(self.a, key, "review", text=review, scope="shared", version=1)
        self.assertEqual(self.item(self.b, key)["reviews"][0]["owner"], "alice")
        for actor in (self.a, self.b):
            ctx = self.suggest(actor, "shared", "@AI 请给周末出门的建议")
            self.assertEqual(
                [(r["owner"], r["text"]) for r in ctx["activity_experiences"]],
                [("alice", review)],
            )
        self.write(
            self.b,
            key,
            "review",
            owner="alice",
            text="覆盖",
            scope="shared",
            expected=422,
        )
        self.write(self.b, key, "review/withdraw", method="POST")
        self.assertEqual(self.item(self.a, key)["reviews"][0]["text"], review)
        self.write(
            self.a, key, "review", text="更喜欢沿河散步", scope="shared", version=2
        )
        ctx = self.suggest(self.b, "shared", "@AI 推荐周末约会")
        self.assertEqual(
            [r["text"] for r in ctx["activity_experiences"]], ["更喜欢沿河散步"]
        )
        self.write(self.a, key, "review", text="沿河散步", scope="private", version=3)
        ctx = self.suggest(self.b, "shared", "@AI 推荐周末约会")
        self.assertEqual(ctx["activity_experiences"], [])
        self.assertEqual(self.item(self.b, key)["reviews"], [])
        rebuilt, _ = fixture_app(self.folder.name)
        with TestClient(rebuilt) as client:
            states = [
                client.get("/v1/state", headers=h).json()["activities"][0]
                for h in (self.a, self.b)
            ]
            self.assertEqual(states[0]["reviews"][0]["text"], "沿河散步")
            self.assertEqual(states[1]["reviews"], [])
        self.write(self.a, key, "review/withdraw", method="POST", version=4)
        self.write(self.a, key, "review/withdraw", method="POST", version=4)
        self.assertEqual(self.item(self.a, key)["reviews"], [])
        self.assertEqual(
            self.suggest(self.a, "private", "推荐周末约会")["activity_experiences"], []
        )
        self.write(
            self.a, key, "review", text=review, scope="private", version=0, expected=409
        )
        self.write(self.a, key, "steps/happened", enabled=False, version=1)
        self.assertIsNone(self.item(self.a, key)["steps"]["happened"]["at"])
