import sqlite3
import unittest
from contextlib import closing
from datetime import datetime
from pathlib import Path
from tempfile import TemporaryDirectory

from fastapi.testclient import TestClient

from ..daily_portrait import SHANGHAI, refresh_due
from .fixture import fixture_app


class DailyPortraitTests(unittest.TestCase):
    def setUp(self):
        self.folder = TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.app, self.upstream = fixture_app(self.folder.name)
        self.client = TestClient(self.app).__enter__()
        self.addCleanup(self.client.__exit__, None, None, None)
        self.a = self.login("a")
        self.b = self.login("b")
        self.stamp = datetime(2026, 1, 16, 23, 55, tzinfo=SHANGHAI)
        self.boundary = datetime(2026, 1, 17, 0, 0, tzinfo=SHANGHAI)

    def login(self, who):
        rsp = self.client.post(
            "/v1/login",
            json={"email": who + "@example.test", "password": "fixture-only"},
        )
        self.assertEqual(rsp.status_code, 200, rsp.text)
        return {"Authorization": "Bearer " + rsp.json()["token"]}

    def state(self, headers):
        rsp = self.client.get("/v1/state", headers=headers)
        self.assertEqual(rsp.status_code, 200, rsp.text)
        return rsp.json()

    def post_memory(self, key, phrase="我不喜欢人多"):
        rsp = self.client.post(
            "/v1/messages",
            headers=self.a,
            json={"scope": "private", "text": phrase, "request_id": key},
        )
        self.assertEqual(rsp.status_code, 200, rsp.text)
        return self.state(self.a)["memories"][-1]

    def set_clock(self, memory):
        with self.app.state.db.connection(True) as c:
            touched = c.execute(
                "UPDATE portrait_sources SET changed_at=? WHERE memory=?",
                (int(self.stamp.timestamp()), memory["id"]),
            )
            self.assertEqual(touched.rowcount, 1)

    def test_midnight_private_candidate_confirm_correct_delete(self):
        m = self.post_memory("normal-private-1")
        self.set_clock(m)
        self.assertEqual(refresh_due(self.app.state.db, self.stamp), 0)
        self.assertIsNone(self.state(self.a)["daily_portrait"])
        self.assertEqual(refresh_due(self.app.state.db, self.boundary), 1)
        self.assertEqual(refresh_due(self.app.state.db, self.boundary), 0)
        first = self.state(self.a)["daily_portrait"]
        self.assertEqual(first["as_of"], "2026-01-17")
        self.assertEqual(first["pending"][0]["text"], m["text"])
        self.assertEqual(first["observations"], [])
        self.assertIsNone(self.state(self.b)["daily_portrait"])
        self.assertEqual(self.state(self.b)["profiles"], [])
        self.assertEqual(len(self.upstream.contexts), 1)

        path = "/v1/memories/" + m["id"]
        rsp = self.client.put(
            path,
            headers=self.a,
            json={"scope": "private", "text": "我喜欢安静的地方", "version": 1},
        )
        self.assertEqual(rsp.status_code, 200)
        portrait = self.state(self.a)["daily_portrait"]
        self.assertEqual(portrait["pending"], [])
        self.assertEqual(portrait["observations"][0]["text"], "我喜欢安静的地方")
        self.assertEqual(
            self.client.delete(path + "?version=2", headers=self.a).status_code, 200
        )
        self.assertIsNone(self.state(self.a)["daily_portrait"])
        self.assertIsNone(self.state(self.b)["daily_portrait"])

    def test_dismiss_and_profile_deletion_do_not_reappear_on_catchup(self):
        first = self.post_memory("old-private-chat")
        second = self.post_memory("new-private-chat")
        for m in (first, second):
            self.set_clock(m)
        self.assertEqual(refresh_due(self.app.state.db, self.boundary), 2)
        path = "/v1/memories/" + first["id"] + "?version=1"
        self.assertEqual(self.client.delete(path, headers=self.a).status_code, 200)
        pending = self.state(self.a)["daily_portrait"]["pending"]
        self.assertEqual([p["id"] for p in pending], [second["id"]])
        self.assertEqual(
            self.client.delete("/v1/profile?version=0", headers=self.a).status_code, 200
        )
        self.assertIsNone(self.state(self.a)["daily_portrait"])
        rebuilt, _ = fixture_app(self.folder.name)
        with TestClient(rebuilt) as restarted:
            self.assertIsNone(
                restarted.get("/v1/state", headers=self.a).json()["daily_portrait"]
            )

    def test_upgrade_backfills_only_current_records_and_catches_up_on_start(self):
        memory = self.post_memory("existing-private")
        with (
            closing(sqlite3.connect(Path(self.folder.name) / "product.sqlite3")) as c,
            c,
        ):
            # Simulate data left by a pre-feature installation before an outage.
            c.execute("PRAGMA user_version=2")
            c.execute("DELETE FROM portrait_sources")
            c.execute("UPDATE chats SET at=1")
        restarted, upstream = fixture_app(self.folder.name)
        with TestClient(restarted) as client:
            res = client.get("/v1/state", headers=self.a)
            self.assertEqual(res.status_code, 200, res.text)
            pending = res.json()["daily_portrait"]["pending"]
            self.assertEqual([p["id"] for p in pending], [memory["id"]])
            self.assertEqual(upstream.contexts, [])
