"""Two independent product sessions, synthetic Open WebUI channel and model."""

import tempfile
import unittest
from uuid import uuid4

from fastapi.testclient import TestClient

from .fixture import fixture_app


MOVIE = "下次一起挑电影，接着看上次那部"


class MandateTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.boot()
        self.a, self.b = self.login("a"), self.login("b")

    def boot(self):
        app, self.up = fixture_app(self.folder.name)
        self.client = self.enterContext(TestClient(app))

    def login(self, name):
        response = self.client.post(
            "/v1/login",
            json={
                "email": name + "@example.test",
                "password": "fixture-only",
            },
        )
        self.assertEqual(response.status_code, 200)
        return {"Authorization": "Bearer " + response.json()["token"]}

    def call(self, who, method, path, body=None, expected=200):
        resp = self.client.request(method, "/v1/" + path, headers=who, json=body)
        self.assertEqual(resp.status_code, expected, resp.text)
        return resp.json()

    def say(self, who, text, scope="shared"):
        self.call(
            who,
            "POST",
            "messages",
            {
                "scope": scope,
                "text": text,
                "request_id": str(uuid4()),
            },
        )

    def state(self, who):
        return self.call(who, "GET", "state")

    def test_shared_lifecycle_and_topic_recall(self):
        self.say(self.a, MOVIE)
        first = self.state(self.b)
        message = first["messages"]["shared"][-1]
        self.assertFalse(first["mandates"])
        self.assertFalse(self.up.contexts)
        create = {
            "source_id": message["id"],
            "source_text": MOVIE,
            "task": "接着看上次那部",
            "cue": "一起挑电影",
        }
        key = self.call(self.b, "POST", "mandates", create)["id"]
        self.assertEqual(self.call(self.a, "POST", "mandates", create)["id"], key)
        self.assertFalse(self.up.contexts)
        self.assertEqual(self.state(self.a)["mandates"], self.state(self.b)["mandates"])
        (row,) = self.state(self.a)["mandates"]
        self.assertEqual(
            (row["owner"], row["source_owner"], row["source_text"]),
            ("bob", "alice", MOVIE),
        )
        self.assertGreater(row["source_at"], 0)
        self.say(self.a, "今晚看什么？")
        self.assertFalse(self.up.contexts)

        def ask(text, matched):
            self.say(self.b, text)
            rows = self.up.contexts[-1][1]["mandates"]
            self.assertEqual(
                [r["task"] for r in rows], [create["task"]] if matched else []
            )
            if matched:
                reply = self.state(self.a)["messages"]["shared"][-1]
                self.assertEqual(reply["role"], "assistant")
                self.assertIn(create["task"], reply["text"])

        ask("@AI 今晚吃什么？", False)
        ask("@AI 我看过电影了", False)
        ask("@AI 那部电影是什么时候上映的？", False)
        ask("@AI 今晚看什么？", True)
        self.say(self.a, "帮我挑一部电影", "private")
        self.assertEqual(self.up.contexts[-1][1]["mandates"][0]["id"], key)
        path = "mandates/" + key
        paused = {"status": "paused", "version": 1}
        self.call(self.b, "PUT", path, paused)
        self.call(self.b, "PUT", path, paused)
        self.call(self.a, "PUT", path, {"status": "completed", "version": 1}, 409)
        ask("@AI 推荐一部电影", False)
        self.boot()
        self.a, self.b = self.login("a"), self.login("b")
        self.assertEqual(self.state(self.a)["mandates"][0]["status"], "paused")
        self.call(self.a, "PUT", path, {"status": "active", "version": 2})
        ask("@AI 今晚看什么？", True)
        self.call(self.b, "PUT", path, {"status": "completed", "version": 3})
        ask("@AI 今晚看什么？", False)
        self.assertEqual(self.state(self.a)["mandates"], self.state(self.b)["mandates"])
        self.assertEqual(self.state(self.a)["mandates"][0]["status"], "completed")
        self.call(self.a, "PUT", path, {"status": "active", "version": 4}, 409)

    def test_source_must_be_current_shared_human_message_and_cancel(self):
        self.say(self.a, "惊喜内容只留给我", "private")
        private = self.state(self.a)["messages"]["private"][0]
        body = {
            "source_text": private["text"],
            "source_id": private["id"],
            "cue": "准备惊喜",
            "task": "给对方一个提醒",
        }
        self.call(self.b, "POST", "mandates", body, 404)
        self.say(self.a, "@AI 今晚吃什么？")
        assistant = self.state(self.a)["messages"]["shared"][-1]
        self.call(
            self.a,
            "POST",
            "mandates",
            body
            | {
                "source_id": assistant["id"],
                "source_text": assistant["text"],
            },
            404,
        )
        self.say(self.a, "下次去海洋馆，记得水母展")
        message = self.state(self.b)["messages"]["shared"][-1]
        body.update(
            source_id=message["id"],
            source_text=message["text"],
            task="看水母展",
            cue="去海洋馆",
        )
        self.call(self.b, "POST", "mandates", body | {"source_text": "原话已变"}, 409)
        self.assertFalse(self.state(self.b)["mandates"])
        key = self.call(self.b, "POST", "mandates", body)["id"]
        self.say(self.b, "@AI 推荐个海洋馆")
        self.assertEqual(self.up.contexts[-1][1]["mandates"][0]["id"], key)
        self.call(
            self.a, "PUT", "mandates/" + key, {"version": 1, "status": "cancelled"}
        )
        self.say(self.b, "@AI 推荐个海洋馆")
        self.assertEqual(self.up.contexts[-1][1]["mandates"], [])
        self.assertEqual(self.state(self.a)["mandates"][0]["status"], "cancelled")
        self.up.forbidden.add("bob")
        self.call(
            self.b, "PUT", "mandates/" + key, {"version": 2, "status": "active"}, 403
        )
