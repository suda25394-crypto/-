from contextlib import closing
from concurrent.futures import ThreadPoolExecutor
from tempfile import TemporaryDirectory
import json
import sqlite3
import unittest
from pathlib import Path

from fastapi.testclient import TestClient
from .fixture import fixture_app


class ProductTests(unittest.TestCase):
    def setUp(self):
        self.folder = TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        app, self.source = fixture_app(self.folder.name)
        self.client = TestClient(app).__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)
        self.a = self.login("a")
        self.b = self.login("b")

    def login(self, user):
        res = self.client.post(
            "/v1/login",
            json={"email": user + "@example.test", "password": "fixture-only"},
        )
        assert res.status_code == 200, res.text
        return {"Authorization": "Bearer " + res.json()["token"]}

    def call(self, method, endpoint, actor, body=None, code=200):
        res = self.client.request(method, "/v1/" + endpoint, headers=actor, json=body)
        self.assertEqual(res.status_code, code, res.text)
        return res.json()

    def state(self, actor):
        return self.call("GET", "state", actor)

    def msg(self, actor, scope, text, request, code=200):
        return self.call(
            "POST",
            "messages",
            actor,
            {"scope": scope, "text": text, "request_id": request},
            code,
        )

    def test_pair_profile_memory_context_and_continuity(self):
        self.call(
            "POST",
            "login",
            {},
            {"email": "outsider@example.test", "password": "fixture-only"},
            403,
        )
        self.msg(self.a, "private", "我不喜欢人多", "private-0001")
        a = self.state(self.a)
        b = self.state(self.b)
        memory = a["memories"][0]
        self.assertEqual(memory["scope"], "candidate")
        self.assertNotIn("人多", json.dumps(b, ensure_ascii=False))
        self.call(
            "PUT",
            "memories/" + memory["id"],
            self.b,
            {"scope": "shared", "version": 1, "text": "other"},
            404,
        )
        self.msg(self.b, "shared", "@AI 周六出门预算200", "channel-0001")
        self.assertFalse(self.source.contexts[-1][1]["memories"])
        self.call(
            "PUT",
            "memories/" + memory["id"],
            self.a,
            {"scope": "shared", "version": 1, "text": "我不喜欢人多"},
        )
        self.msg(self.b, "shared", "@AI 周六出门预算200", "channel-0002")
        self.assertEqual(
            self.source.contexts[-1][1]["memories"][0]["text"], "我不喜欢人多"
        )
        b = self.state(self.b)
        self.assertEqual(
            b["messages"]["shared"][-1]["text"], "【合成模型回执】选择安静场所"
        )
        self.assertEqual(
            self.state(self.a)["messages"]["shared"], b["messages"]["shared"]
        )
        draft = b["drafts"][0]
        items = draft["items"]
        items[0]["body"] = "改到 16:00"
        args = {"version": 1, "items": items}

        def confirm(actor):
            return self.call("POST", "drafts/" + draft["id"] + "/confirm", actor, args)

        with ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(confirm, [self.a, self.b]))
        modules = self.state(self.a)["modules"]
        self.assertEqual(len(modules), 2)
        self.assertIn("改到 16:00", [m["body"] for m in modules])
        self.assertEqual(modules, self.state(self.b)["modules"])
        self.call(
            "PUT",
            "memories/" + memory["id"],
            self.a,
            {"scope": "private", "version": 2, "text": "上午散步"},
        )
        self.msg(self.b, "shared", "@AI 再推荐一次", "channel-0003")
        self.assertNotIn(
            "人多", json.dumps(self.source.contexts[-1], ensure_ascii=False)
        )
        self.assertIn(
            {"module": "date", "action": "edited"},
            self.source.contexts[-1][1]["feedback"],
        )
        self.assertFalse(self.state(self.b)["memories"])
        self.call("DELETE", "memories/" + memory["id"] + "?version=3", self.a)
        self.assertFalse(self.state(self.a)["memories"])
        newapp, _ = fixture_app(self.folder.name)
        with TestClient(newapp) as rebuilt:
            restored = rebuilt.get("/v1/state", headers=self.b)
            self.assertEqual(restored.status_code, 200)
            self.assertEqual(restored.json()["modules"], modules)
        self.call("POST", "logout", self.b)
        self.call("GET", "state", self.b, code=401)

    def test_profile_copy_and_owner_only_questions(self):
        first = {"life": {"avoid": "拥挤"}, "communication": {}}
        self.call(
            "PUT", "profile", self.a, {"version": 0, "published": True, "data": first}
        )
        private = {"life": {"avoid": "私人修订"}, "communication": {}}
        self.call(
            "PUT",
            "profile",
            self.a,
            {"version": 1, "published": False, "data": private},
        )
        self.assertEqual(
            self.state(self.b)["profiles"][0]["data"]["life"], first["life"]
        )
        self.assertEqual(
            self.state(self.a)["profiles"][0]["data"]["life"], private["life"]
        )
        self.call(
            "PUT",
            "profile",
            self.a,
            {"version": 2, "published": True, "data": private, "owner": "bob"},
            422,
        )
        self.call("POST", "profile/withdraw", self.a, {"version": 2})
        self.assertFalse(self.state(self.b)["profiles"])
        self.call("DELETE", "profile?version=3", self.a)
        self.assertEqual(self.state(self.a)["profiles"][0]["data"], {})

    def test_secret_plan_cancel_and_disallow_cross_actor_mutation(self):
        self.msg(self.a, "private", "给她准备一个秘密惊喜", "secret-0001")
        draft = self.state(self.a)["drafts"][0]
        self.assertEqual(self.state(self.b)["drafts"], [])
        self.assertEqual(self.state(self.b)["messages"]["shared"], [])
        self.call(
            "POST", "drafts/" + draft["id"] + "/confirm", self.b, {"version": 1}, 404
        )
        self.call("POST", "drafts/" + draft["id"] + "/cancel", self.a, {"version": 1})
        self.call(
            "POST", "drafts/" + draft["id"] + "/confirm", self.a, {"version": 1}, 409
        )
        self.assertEqual(self.state(self.b)["modules"], [])
        self.msg(self.b, "shared", "@AI 请帮忙", "shared-9999")
        self.assertFalse(self.source.contexts[-1][1]["feedback"])
        self.assertNotIn(
            "惊喜", json.dumps(self.source.contexts[-1], ensure_ascii=False)
        )

    def test_safe_retry_limits_and_member_revocation(self):
        self.source.disabled = True
        self.msg(self.a, "shared", "@AI 周六计划", "shared-disabled", 503)
        self.assertEqual(len(self.state(self.b)["messages"]["shared"]), 1)
        self.assertEqual(
            self.state(self.a)["pending_messages"][0]["request_id"], "shared-disabled"
        )
        self.assertFalse(self.state(self.b)["pending_messages"])
        self.source.disabled = False
        self.msg(self.a, "shared", "@AI 周六计划", "shared-disabled")
        self.msg(self.a, "shared", "@AI 周六计划", "shared-disabled")
        self.assertEqual(len(self.state(self.b)["messages"]["shared"]), 2)
        self.assertFalse(self.state(self.a)["pending_messages"])
        self.assertEqual(len(self.source.contexts), 1)
        self.msg(self.a, "shared", "changed", "shared-disabled", 409)
        self.source.fail_after_post = True
        self.msg(self.a, "shared", "一起吃晚饭", "shared-post-retry", 503)
        self.msg(self.a, "shared", "一起吃晚饭", "shared-post-retry")
        self.assertEqual(len(self.state(self.b)["messages"]["shared"]), 3)
        self.source.forbidden.add("bob")
        self.call("GET", "state", self.b, code=403)
        self.call("POST", "logout", self.b)
        self.call("GET", "state", self.b, code=401)

    def test_manual_module_conflict_and_schema_validation(self):
        req = {
            "request_id": "manual-record",
            "module": "wish",
            "title": "看海",
            "body": "下午出发",
            "confirmed": True,
        }
        self.call("POST", "modules", self.a, req | {"confirmed": False}, 422)
        self.call("POST", "modules", self.a, req)
        self.call("POST", "modules", self.a, req)
        rows = self.state(self.b)["modules"]
        self.assertEqual(len(rows), 1)
        self.assertEqual(self.state(self.a)["drafts"], [])
        path = "modules/" + rows[0]["id"]
        self.call("PUT", path, self.b, {"version": 1, "title": "看海", "body": "周日"})
        self.call(
            "PUT", path, self.a, {"version": 1, "title": "修改", "body": "已过期"}, 409
        )
        self.source.bad_output = True
        self.msg(self.a, "private", "周六出门", "schema-invalid", 502)
        self.assertEqual(len(self.state(self.a)["modules"]), 1)
        self.call(
            "POST",
            "messages",
            self.a,
            {"scope": "shared", "text": " ", "request_id": "bad-input"},
            422,
        )

    def test_quota_is_persistent_across_api_restart(self):
        with TemporaryDirectory() as folder:
            app, source = fixture_app(folder, daily=1)
            with TestClient(app) as caller:
                tok = caller.post(
                    "/v1/login",
                    json={"email": "a@example.test", "password": "fixture-only"},
                ).json()["token"]
                headers = {"Authorization": "Bearer " + tok}
                req = {"scope": "private", "text": "hello", "request_id": "quota-first"}
                self.assertEqual(
                    caller.post("/v1/messages", headers=headers, json=req).status_code,
                    200,
                )
            app, _ = fixture_app(folder, daily=1)
            with TestClient(app) as caller:
                blocked = caller.post(
                    "/v1/messages",
                    headers=headers,
                    json=req | {"request_id": "quota-next"},
                )
                self.assertEqual(blocked.status_code, 429)
            with closing(sqlite3.connect(Path(folder) / "product.sqlite3")) as c:
                usage = c.execute(
                    "SELECT outcome,in_tokens,out_tokens FROM usage"
                ).fetchall()
                self.assertEqual(usage, [("returned", 10, 12)])
                encrypted = c.execute("SELECT upstream,digest FROM sessions").fetchone()
                self.assertNotIn(tok, repr(encrypted))

    def test_revocation_during_inference_discards_stale_reply(self):
        from threading import Event

        self.msg(self.a, "private", "我不喜欢人多", "candidate-race")
        m = self.state(self.a)["memories"][0]
        self.call(
            "PUT",
            "memories/" + m["id"],
            self.a,
            {"version": 1, "text": "我不喜欢人多", "scope": "shared"},
        )
        start, release = Event(), Event()
        generate = self.source.complete

        def slow(*args):
            answer = generate(*args)
            start.set()
            if not release.wait(8):
                raise RuntimeError("Test timed out")
            return answer

        self.source.complete = slow
        with ThreadPoolExecutor(max_workers=1) as pool:
            response = pool.submit(
                self.msg, self.b, "shared", "@AI 周六计划", "race-retry", 409
            )
            self.assertTrue(start.wait(4))
            self.call("DELETE", "memories/" + m["id"] + "?version=2", self.a)
            release.set()
            self.assertEqual(response.result()["error"]["code"], "context_changed")
        self.assertFalse(self.state(self.a)["drafts"])
        self.assertEqual(len(self.state(self.a)["messages"]["shared"]), 1)
        self.msg(self.b, "shared", "@AI 周六计划", "race-retry")
        self.assertFalse(self.source.contexts[-1][1]["memories"])
        self.assertEqual(len(self.state(self.a)["messages"]["shared"]), 2)

    def test_reject_candidate_and_uncertain_model_do_not_replay(self):
        self.msg(self.a, "private", "我不喜欢人多", "reject-candidate")
        m = self.state(self.a)["memories"][0]
        self.call("DELETE", "memories/" + m["id"] + "?version=1", self.a)
        self.msg(self.a, "private", "重新推荐", "after-reject")
        self.assertNotIn(
            "人多", json.dumps(self.source.contexts[-1], ensure_ascii=False)
        )
        self.source.bad_output = True
        self.msg(self.a, "private", "周六预算", "invalid-retry", 502)
        self.msg(self.a, "private", "周六预算", "invalid-retry", 409)
        self.assertEqual(len(self.source.contexts), 3)
