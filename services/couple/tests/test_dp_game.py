"""Dual user tests with a persistent product database and an isolated synthetic model."""

import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Event
from concurrent.futures import ThreadPoolExecutor

import httpx
from fastapi.testclient import TestClient

from .fixture import fixture_app
from services.couple.upstream import Upstream, UpstreamConfig, UpstreamError


class GameTests(unittest.TestCase):
    def setUp(self):
        self.folder = TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.start()
        self.a, self.b = (self.login(who) for who in ("a", "b"))
        self.memory = self.module(
            "memory", "雨后的河边书摊", "雨停后我们在河边书摊选了两本旧书。"
        )
        self.args = {"request_id": "new-game-0001", "source_ids": [self.memory]}

    def start(self):
        app, self.model = fixture_app(self.folder.name)
        self.client = TestClient(app).__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)

    def login(self, who):
        response = self.client.post(
            "/v1/login",
            json={"email": who + "@example.test", "password": "fixture-only"},
        )
        self.assertEqual(response.status_code, 200)
        return {"Authorization": "Bearer " + response.json()["token"]}

    def call(self, method, route, who, json=None, status=200):
        res = self.client.request(method, "/v1/" + route, headers=who, json=json)
        self.assertEqual(res.status_code, status, res.text)
        return res.json()

    def module(self, kind, title, body):
        self.call(
            "POST",
            "modules",
            self.a,
            {
                "module": kind,
                "title": title,
                "body": body,
                "request_id": "module-for-test-" + kind,
                "confirmed": True,
            },
        )
        modules = self.call("GET", "state", self.a)["modules"]
        return next(m["id"] for m in modules if m["title"] == title)

    def test_two_roles_resume_and_mutual_reveal(self):
        g = self.call("POST", "games", self.a, self.args)
        route = "games/" + g["id"] + "/"
        self.assertEqual(len(g["questions"]), 3)
        self.assertEqual(self.call("POST", "games", self.a, self.args), g)
        self.assertEqual(len(self.model.contexts), 1)
        self.assertEqual(set(self.model.contexts[0][1][0]), {"id", "title", "body"})
        selected = {"choices": [2, None, None], "version": 0}
        partial = self.call("PUT", route + "choices", self.a, selected)
        self.assertEqual(partial["version"], 1)
        self.assertEqual(self.call("PUT", route + "choices", self.a, selected), partial)
        self.call("POST", route + "lock", self.a, selected, 422)
        # Reopen the service on the same DB; both existing client sessions still work.
        self.start()
        a = self.call("GET", "state", self.a)["games"][0]
        b = self.call("GET", "state", self.b)["games"][0]
        self.assertEqual((a["role"], b["role"]), ("answer", "guess"))
        self.assertEqual(a["my_choices"], [2, None, None])
        self.assertEqual(b["my_choices"], [None, None, None])
        self.assertNotIn("result", b)
        a = self.call(
            "POST", route + "lock", self.a, {"version": 1, "choices": [2, 1, 0]}
        )
        self.call(
            "PUT", route + "choices", self.a, {"version": 2, "choices": [0, 1, 0]}, 409
        )
        self.call("POST", route + "reveal", self.a, status=409)
        b = self.call(
            "POST", route + "lock", self.b, {"version": 0, "choices": [0, 1, 0]}
        )
        self.assertNotIn("result", b)
        self.assertEqual(
            set(b),
            {
                "id",
                "role",
                "questions",
                "my_choices",
                "version",
                "my_locked",
                "other_locked",
                "my_consent",
                "other_consent",
            },
        )
        self.assertNotIn("result", self.call("POST", route + "reveal", self.a))
        self.assertNotIn("result", self.call("GET", "state", self.b)["games"][0])
        both = self.call("POST", route + "reveal", self.b)["result"]
        self.assertEqual(both, {"answers": [2, 1, 0], "guesses": [0, 1, 0], "score": 2})
        self.assertEqual(both, self.call("POST", route + "reveal", self.b)["result"])
        self.assertEqual(both, self.call("GET", "state", self.a)["games"][0]["result"])
        self.assertEqual(self.model.contexts, [])
        # Updating a source retires stale questions/results for both participants.
        self.call(
            "PUT",
            "modules/" + self.memory,
            self.a,
            {"version": 1, "title": "重新整理", "body": "回忆修订"},
        )
        self.assertEqual(self.call("GET", "state", self.b)["games"], [])
        self.call("POST", route + "reveal", self.a, status=404)

    def test_foreign_material_and_invalid_questions(self):
        other = self.module("wish", "未来旅行", "想去下一座城市。")
        self.call("POST", "games", self.a, self.args | {"source_ids": [other]}, 404)
        self.call("POST", "games", self.a, self.args | {"source_ids": []}, 422)
        self.call(
            "POST",
            "games",
            self.a,
            self.args | {"source_ids": [self.memory, self.memory]},
            422,
        )
        self.assertEqual(self.model.contexts, [])
        real = self.model.generate_game
        request = 0
        for change, code in [
            (lambda qs: qs.clear(), "insufficient_memories"),
            (lambda qs: qs.pop(), "game_format"),
            (lambda qs: qs[0].update(source_id=other), "game_format"),
            (lambda qs: qs[1].update(anchor="不存在的片段"), "game_format"),
            (lambda qs: qs[0].update(options=["a", "a", "b"]), "game_format"),
            (lambda qs: qs[0].update(answer=1), "game_format"),
        ]:

            def broken(token, sources):
                obj = real(token, sources)
                change(obj["questions"])
                return obj

            self.model.generate_game = broken
            request += 1
            body = self.args | {"request_id": "bad-game-" + str(request)}
            for _ in range(2):
                outcome = self.call(
                    "POST",
                    "games",
                    self.a,
                    body,
                    422 if code == "insufficient_memories" else 502,
                )
                self.assertEqual(outcome["error"]["code"], code)
            self.assertEqual(self.call("GET", "state", self.b)["games"], [])
        self.assertEqual(len(self.model.contexts), request)

    def test_model_rejection_retry_uncertainty_and_shared_budget(self):
        self.model.disabled = True
        self.call("POST", "games", self.a, self.args, 503)
        self.model.disabled = False
        self.call("POST", "games", self.a, self.args)
        calls = []

        def lost(*args):
            calls.append(True)
            raise UpstreamError("model_outcome_unknown", "回执中断", 502)

        self.model.generate_game = lost
        body = self.args | {"request_id": "separate-game"}
        self.call("POST", "games", self.b, body, 502)
        self.assertEqual(
            self.call("POST", "games", self.b, body, 409)["error"]["code"],
            "generation_unknown",
        )
        self.assertEqual(len(calls), 1)
        self.assertEqual(
            self.call("GET", "state", self.b)["game_generation_status"], "unknown"
        )
        self.assertIsNone(self.call("GET", "state", self.a)["game_generation_status"])
        app, model = fixture_app(self.folder.name, daily=2)
        with TestClient(app) as limit_client:
            self.assertEqual(
                limit_client.post(
                    "/v1/games",
                    headers=self.a,
                    json=self.args | {"request_id": "budget-probe"},
                ).status_code,
                429,
            )
            self.assertEqual(
                limit_client.post(
                    "/v1/messages",
                    headers=self.b,
                    json={
                        "request_id": "budget-chat",
                        "scope": "private",
                        "text": "周末见面",
                    },
                ).status_code,
                429,
            )
            self.assertFalse(model.contexts)

    def test_inflight_duplicate_and_source_edit(self):
        entered, release = Event(), Event()
        real = self.model.generate_game

        def wait_model(*args):
            entered.set()
            self.assertTrue(release.wait(8))
            return real(*args)

        self.model.generate_game = wait_model
        with ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(self.call, "POST", "games", self.a, self.args, 409)
            try:
                self.assertTrue(entered.wait(8))
                self.call("POST", "games", self.a, self.args, 409)
                self.call(
                    "PUT",
                    "modules/" + self.memory,
                    self.b,
                    {"version": 1, "title": "更新", "body": "新素材"},
                )
            finally:
                release.set()
            self.assertEqual(future.result()["error"]["code"], "source_changed")
        self.assertEqual(self.call("GET", "state", self.a)["games"], [])
        self.assertEqual(len(self.model.contexts), 1)


class GatewayGameTests(unittest.TestCase):
    def test_production_connector_authorizes_user_then_sends_only_material(self):
        with TemporaryDirectory() as folder:
            cfg = UpstreamConfig(
                "http://webui.test",
                "http://gateway.test",
                "pair",
                frozenset({"a", "b"}),
                "x" * 32,
                str(Path(folder) / "db"),
            )
            sources = [{"id": "entry", "title": "雨后", "body": "一起看书"}]
            grant = True
            seen = []

            def provider(req):
                seen.append(req.url.path)
                if req.url.host == "webui.test":
                    self.assertEqual(req.headers["authorization"], "Bearer session-A")
                    return httpx.Response(
                        200, json={"data": [{"id": "deepseek-flash"}] if grant else []}
                    )
                self.assertEqual(req.headers["authorization"], "Bearer " + "x" * 32)
                body = json.loads(req.content)
                self.assertEqual(body["model"], "deepseek-flash")
                self.assertLessEqual(body["max_tokens"], 1024)
                self.assertLessEqual(len(req.content), 16384)
                self.assertEqual(
                    json.loads(body["messages"][1]["content"]),
                    {"shared_memories": sources},
                )
                return httpx.Response(
                    200,
                    json={"choices": [{"message": {"content": '{"questions":[]}'}}]},
                )

            up = Upstream(cfg, httpx.MockTransport(provider))
            self.assertEqual(up.generate_game("session-A", sources)["questions"], [])
            grant = False
            with self.assertRaises(UpstreamError):
                up.generate_game("session-A", sources)
            self.assertEqual(
                seen, ["/api/models", "/v1/chat/completions", "/api/models"]
            )
