"""D-45/46 two handset sessions against the product API, synthetic provider only."""

import json
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from tempfile import TemporaryDirectory
from threading import Event
import unittest

from fastapi.testclient import TestClient

from ..daily_portrait import SHANGHAI, refresh_due
from .fixture import fixture_app


class ConversationalPortraitTests(unittest.TestCase):
    def setUp(self):
        self.room = self.enterContext(TemporaryDirectory())
        self.app, self.provider = fixture_app(self.room)
        self.client = self.enterContext(TestClient(self.app))
        self.seq = 0
        self.a = self.login("a")
        self.b = self.login("b")

    def login(self, owner):
        response = self.client.post(
            "/v1/login",
            json={"email": owner + "@example.test", "password": "fixture-only"},
        )
        response.raise_for_status()
        return {"Authorization": "Bearer " + response.json()["token"]}

    def call(self, actor, method, path, body=None, code=200):
        res = self.client.request(method, "/v1/" + path, headers=actor, json=body)
        self.assertEqual(res.status_code, code, res.text)
        return res.json()

    def state(self, a):
        return self.call(a, "GET", "state")

    def say(self, a, text, scope="private", req=None):
        self.seq += 1
        return self.call(
            a,
            "POST",
            "messages",
            {
                "request_id": req or f"portrait-{self.seq:04}",
                "scope": scope,
                "text": text,
            },
        )

    def test_private_consent_public_correction_withdrawal_and_reopen(self):
        original = "出游时每天最多安排一件主要的事"
        self.say(self.a, original)
        mine = self.state(self.a)
        self.assertEqual(mine["memories"][0]["text"], original)
        self.assertEqual(mine["memories"][0]["scope"], "candidate")
        self.assertIn(original, mine["messages"]["private"][-1]["text"])
        self.assertNotIn(original, json.dumps(self.state(self.b), ensure_ascii=False))
        self.say(self.b, "@DP 推荐出游行程", "shared")
        self.assertNotIn(
            original, json.dumps(self.provider.contexts[-1][1], ensure_ascii=False)
        )
        before = len(self.provider.contexts)
        self.say(self.a, "这句可以给她看", req="publish-once")
        self.say(self.a, "这句可以给她看", req="publish-once")
        shared = self.state(self.b)["memories"]
        self.assertEqual(len(shared), 1)
        self.assertEqual(
            (shared[0]["text"], shared[0]["scope"], shared[0]["version"]),
            (original, "shared", 2),
        )
        self.assertEqual(len(self.provider.contexts), before)
        self.say(self.b, "@DP 推荐旅行计划", "shared")
        self.assertIn(
            original,
            json.dumps(self.provider.contexts[-1][1]["memories"], ensure_ascii=False),
        )
        self.say(self.a, "改成出游时每天最多一个主要安排，可以给她看")
        corrected = "出游时每天最多一个主要安排"
        b = self.state(self.b)
        self.assertEqual([m["text"] for m in b["memories"]], [corrected])
        self.assertNotIn(original, json.dumps(b["memories"], ensure_ascii=False))
        self.assertFalse(b["profile_focus"])
        self.assertFalse(b["messages"]["private"])
        self.say(self.a, "先不公开了")
        self.assertEqual(self.state(self.a)["memories"][0]["scope"], "private")
        self.assertFalse(self.state(self.b)["memories"])
        self.say(self.b, "@DP 推荐周末出游", "shared")
        self.assertNotIn(
            corrected, json.dumps(self.provider.contexts[-1][1], ensure_ascii=False)
        )
        memory = self.state(self.a)["memories"][0]
        for who, code in ((self.b, 404), (self.a, 200)):
            self.call(
                who,
                "POST",
                "profile-focus/" + memory["id"],
                {"version": memory["version"]},
                code,
            )
        self.say(self.a, "改为更喜欢自由安排")
        self.assertEqual(self.state(self.a)["memories"][0]["text"], "更喜欢自由安排")
        self.assertFalse(self.state(self.b)["memories"])
        reopened, _ = fixture_app(self.room)
        with TestClient(reopened) as client:
            self.assertEqual(
                client.get("/v1/state", headers=self.a).json()["memories"][0]["text"],
                "更喜欢自由安排",
            )
            self.assertEqual(
                client.get("/v1/state", headers=self.b).json()["memories"], []
            )

    def test_transient_state_does_not_write_even_if_model_guesses(self):
        original = self.provider.complete

        def inference(*args):
            raw = original(*args)
            raw["memories"] = ["长期精力不足"]
            return raw

        self.provider.complete = inference
        self.call(self.a, "POST", "profile-mode/start", {"version": 0})
        self.say(self.a, "我今天很累")
        self.assertFalse(self.state(self.a)["memories"])
        self.assertFalse(self.state(self.b)["memories"])
        self.say(self.a, "我喜欢安静的书店")
        self.assertEqual(
            [m["text"] for m in self.state(self.a)["memories"]], ["我喜欢安静的书店"]
        )

    def test_research_mode_open_skip_exit_and_unrelated_question(self):
        self.say(self.a, "出游时每天最多安排一件主要的事")
        start = self.call(self.a, "POST", "profile-mode/start", {"version": 0})
        self.assertEqual(start["question"]["id"], "shared_novelty")
        self.assertIn("doi", start["question"])
        self.assertFalse(self.state(self.b)["profile_mode"]["active"])
        self.call(
            self.a, "POST", "profile-mode/start", {"version": 1, "scope": "shared"}, 422
        )
        self.call(
            self.a, "POST", "profile-mode/start", {"version": 1, "owner": "bob"}, 422
        )
        self.say(self.a, "上次一起去了植物园")
        self.assertEqual(
            self.provider.contexts[-1][1]["profile_mode"][0]["question"]["id"],
            "shared_novelty",
        )
        self.say(self.a, "日语语法怎么理解？")
        self.assertFalse(self.provider.contexts[-1][1].get("profile_mode"))
        self.say(self.b, "@DP 我也想了解她", "shared")
        self.assertFalse(self.provider.contexts[-1][1].get("profile_mode"))
        second = self.call(self.a, "POST", "profile-mode/skip", {"version": 1})
        self.assertNotEqual(start["question"]["id"], second["question"]["id"])
        self.assertFalse(
            self.call(self.a, "POST", "profile-mode/end", {"version": 2})["active"]
        )
        self.say(self.a, "再聊聊刚才的话题")
        self.assertFalse(self.provider.contexts[-1][1].get("profile_mode"))
        self.assertFalse(self.state(self.a)["profile_mode"]["active"])

    def test_two_sessions_do_not_publish_previous_sentence_while_new_reply_is_pending(
        self,
    ):
        self.say(self.a, "我喜欢安静的书店")
        second_device = self.login("a")
        entered, release = Event(), Event()
        before = self.provider.complete

        def slow(*args):
            entered.set()
            if not release.wait(5):
                raise AssertionError("Test did not release the synthetic provider")
            return before(*args)

        self.provider.complete = slow
        with ThreadPoolExecutor(1) as pool:
            future = pool.submit(self.say, self.a, "我更喜欢安静的车厢")
            try:
                self.assertTrue(entered.wait(3))
                self.say(second_device, "这句可以给她看")
                self.assertFalse(self.state(self.b)["memories"])
                self.assertIn(
                    "具体文字", self.state(self.a)["messages"]["private"][-1]["text"]
                )
            finally:
                release.set()
                future.result(timeout=5)
        self.provider.complete = before
        self.say(second_device, "这句可以给她看")
        self.assertFalse(self.state(self.b)["memories"])
        m = self.state(self.a)["memories"][0]
        self.call(self.a, "POST", "profile-focus/" + m["id"], {"version": 1})
        self.say(self.a, "这句可以给她看")
        self.say(self.a, "跳过")
        self.assertEqual(self.state(self.b)["memories"][0]["id"], m["id"])
        self.call(self.a, "POST", "profile-focus/" + m["id"], {"version": 2})
        self.call(self.a, "POST", "profile-mode/start", {"version": 0})
        self.assertFalse(self.state(self.a)["profile_focus"])

    def test_quoted_authorization_stale_focus_and_overlapping_daily_refresh(self):
        text = "出游时每天最多安排一件主要的事"
        self.say(self.a, text)
        self.say(self.a, "把“这句可以给她看”翻译成日语")
        self.assertFalse(self.state(self.b)["memories"])
        self.say(self.a, "这句可以给她看")
        self.assertFalse(self.state(self.b)["memories"])
        m = self.state(self.a)["memories"][0]
        self.call(self.a, "POST", "profile-focus/" + m["id"], {"version": 1})
        self.call(
            self.a,
            "PUT",
            "memories/" + m["id"],
            {"text": "每天留一些空白", "scope": "private", "version": 1},
        )
        self.say(self.a, "这句可以给她看")
        self.assertIn(
            "核对最新文字", self.state(self.a)["messages"]["private"][-1]["text"]
        )
        self.assertFalse(self.state(self.b)["memories"])
        with self.app.state.db.connection(True) as c:
            c.execute(
                "UPDATE portrait_sources SET changed_at=1 WHERE memory=?", (m["id"],)
            )

        def refresh(_):
            return refresh_due(
                self.app.state.db, datetime(2026, 11, 18, tzinfo=SHANGHAI)
            )

        with ThreadPoolExecutor(2) as pool:
            self.assertEqual(sorted(pool.map(refresh, range(2))), [0, 1])
        self.assertEqual(len(self.state(self.a)["daily_portrait"]["observations"]), 1)
