"""Two-account module conversations, versioned patch confirmation and v1 upgrade."""

import hashlib
import json
from pathlib import Path
import sqlite3
import time
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from ..database import SCHEMA_VERSION, SCHEMA, Settings, encode
from .fixture import FixtureUpstream, fixture_app


class ModuleThreadTests(unittest.TestCase):
    def setUp(self):
        temporary = self.enterContext(TemporaryDirectory())
        app, self.provider = fixture_app(temporary)
        self.client = self.enterContext(TestClient(app))
        self.a, self.b = self.login("a"), self.login("b")
        self.first = self.create("day-trip-1", "周六两站")
        self.second = self.create("day-trip-2", "下月出游")

    def login(self, name):
        login = self.client.post(
            "/v1/login",
            json={
                "email": name + "@example.test",
                "password": "fixture-only",
            },
        )
        return {"Authorization": "Bearer " + login.json()["token"]}

    def call(self, who, method, path, data=None, code=200):
        response = self.client.request(method, "/v1/" + path, headers=who, json=data)
        self.assertEqual(response.status_code, code, response.text)
        return response.json()

    def create(self, key, title):
        self.call(
            self.a,
            "POST",
            "modules",
            {
                "confirmed": True,
                "request_id": key,
                "module": "date",
                "title": title,
                "body": "先吃饭，再去草坪",
            },
        )
        records = self.call(self.a, "GET", "state")["modules"]
        return next(row for row in records if row["title"] == title)

    def read(self, who, record, scope):
        return self.call(
            who, "GET", "modules/" + record["id"] + "/conversation?scope=" + scope
        )

    def send(self, who, record, scope, key, text, version=1, code=200):
        return self.call(
            who,
            "POST",
            "modules/" + record["id"] + "/conversation",
            {
                "version": version,
                "scope": scope,
                "request_id": key,
                "text": text,
            },
            code,
        )

    def test_bound_patch_conflict_cancel_and_idempotent_confirmation(self):
        self.send(self.a, self.first, "shared", "first-patch", "把第二站改成室内书店")
        (draft,) = self.read(self.b, self.first, "shared")["drafts"]
        self.assertEqual(
            (draft["target_id"], draft["target_version"]), (self.first["id"], 1)
        )
        path = "drafts/" + draft["id"] + "/confirm"
        for altered in ([dict(draft["items"][0], module="wish")], draft["items"] * 2):
            self.call(self.b, "POST", path, {"version": 1, "items": altered}, 422)
        self.call(
            self.a,
            "PUT",
            "modules/" + self.first["id"],
            {
                "version": 1,
                "title": "修订时刻",
                "body": "17:00 吃饭",
            },
        )
        self.call(self.b, "POST", path, {"version": 1}, 409)
        self.send(
            self.a,
            self.first,
            "shared",
            "outdated-turn",
            "再改一次",
            version=1,
            code=409,
        )
        updated = self.read(self.b, self.first, "shared")["record"]
        self.assertEqual((updated["version"], updated["body"]), (2, "17:00 吃饭"))
        self.assertEqual(len(self.provider.contexts), 1)

        self.call(self.a, "POST", "drafts/" + draft["id"] + "/cancel", {"version": 1})
        self.assertEqual(
            self.read(self.b, self.first, "shared")["drafts"][0]["status"], "cancelled"
        )
        self.assertEqual(self.read(self.a, self.first, "shared")["record"], updated)
        self.send(self.a, self.first, "shared", "fresh-patch", "改到书店", version=2)
        draft = self.read(self.b, self.first, "shared")["drafts"][0]
        path = "drafts/" + draft["id"] + "/confirm"
        edits = {
            "version": 1,
            "items": [dict(draft["items"][0], body="17:00 吃饭，再去书店")],
        }
        self.call(self.b, "POST", path, edits)
        self.call(self.a, "POST", path, edits)
        final = self.read(self.a, self.first, "shared")["record"]
        self.assertEqual(
            (final["id"], final["version"], final["body"]),
            (self.first["id"], 3, "17:00 吃饭，再去书店"),
        )
        self.assertEqual(self.read(self.b, self.first, "shared")["record"], final)
        self.assertEqual(
            self.read(self.b, self.second, "shared")["record"], self.second
        )
        self.assertEqual(len(self.call(self.b, "GET", "state")["modules"]), 2)
        self.assertEqual(len(self.provider.contexts), 2)

    def test_same_object_and_authorized_thread_only(self):
        self.send(self.a, self.first, "private", "secret-note", "秘密：把终点改到画室")
        self.send(self.a, self.first, "private", "secret-note", "秘密：把终点改到画室")
        self.send(
            self.a,
            self.second,
            "private",
            "secret-note",
            "秘密：把终点改到画室",
            code=409,
        )
        self.send(
            self.a,
            self.first,
            "shared",
            "secret-note",
            "秘密：把终点改到画室",
            code=409,
        )
        self.assertEqual(len(self.provider.contexts), 1)
        private = self.read(self.a, self.first, "private")
        self.assertEqual(len(private["messages"]), 2)
        self.assertEqual(len(private["drafts"]), 1)
        for member, target, scope in (
            (self.b, self.first, "private"),
            (self.b, self.first, "shared"),
            (self.a, self.second, "private"),
            (self.a, self.first, "shared"),
        ):
            thread = self.read(member, target, scope)
            self.assertEqual((thread["messages"], thread["drafts"]), ([], []))
        self.assertEqual(self.call(self.a, "GET", "state")["messages"]["private"], [])
        self.assertNotIn(
            "画室", json.dumps(self.call(self.b, "GET", "state"), ensure_ascii=False)
        )
        self.assertEqual(len(self.provider.contexts), 1)

        self.send(self.a, self.first, "private", "continue-private", "刚才说的终点呢？")
        private_context = self.provider.contexts[-1][1]
        self.assertEqual(
            [x["role"] for x in private_context["conversation"]], ["user", "assistant"]
        )
        self.assertIn("画室", private_context["conversation"][0]["text"])
        self.assertEqual(private_context["module_target"][0]["id"], self.first["id"])
        self.send(self.a, self.first, "shared", "first-shared", "第一站集合")
        self.send(self.b, self.first, "shared", "another-turn", "刚才说的第一站呢？")
        context = self.provider.contexts[-1][1]
        self.assertNotIn("画室", json.dumps(context, ensure_ascii=False))
        self.assertEqual(context["speaker"], [{"id": "bob"}])
        self.assertEqual(
            [t["role"] for t in context["conversation"]], ["user", "assistant"]
        )
        self.assertEqual(context["conversation"][0]["text"], "第一站集合")
        shared = self.read(self.b, self.first, "shared")
        self.assertEqual(len(shared["messages"]), 4)
        self.assertEqual(shared, self.read(self.a, self.first, "shared"))
        self.assertEqual(self.call(self.b, "GET", "state")["messages"]["shared"], [])
        self.send(self.a, self.second, "shared", "other-module", "那一站呢？")
        other = self.provider.contexts[-1][1]
        self.assertEqual(other["conversation"], [])
        self.assertEqual(other["history"], [])
        self.assertEqual(other["module_target"][0]["id"], self.second["id"])

    def test_confirm_keeps_context_but_revoking_memory_excludes_prior_reply(self):
        self.call(
            self.a,
            "POST",
            "messages",
            {
                "scope": "private",
                "request_id": "seed-private-pref",
                "text": "我不喜欢人多",
            },
        )
        (memory,) = self.call(self.a, "GET", "state")["memories"]
        secret = "我不喜欢人多"
        memory_path = "memories/" + memory["id"]
        self.call(
            self.a,
            "PUT",
            memory_path,
            {"text": secret, "scope": "shared", "version": 1},
        )

        original_complete = self.provider.complete

        def reply_with_authorized_evidence(token, scope, text, context):
            response = original_complete(token, scope, text, context)
            self.assertIn(secret, [m["text"] for m in context["memories"]])
            response["reply"] = "合成证据引用：" + secret
            return response

        instruction = "周末约会，把第二站改成室内书店"
        with patch.object(
            self.provider, "complete", side_effect=reply_with_authorized_evidence
        ):
            self.send(self.b, self.first, "shared", "shared-pref-edit", instruction)
        (draft,) = self.read(self.a, self.first, "shared")["drafts"]
        self.call(self.a, "POST", "drafts/" + draft["id"] + "/confirm", {"version": 1})
        self.send(
            self.b,
            self.first,
            "shared",
            "explain-the-edit",
            "刚才为什么修改第二站？",
            version=2,
        )
        context = self.provider.contexts[-1][1]
        self.assertEqual(context["module_target"][0]["version"], 2)
        self.assertEqual(
            context["conversation"],
            [
                {"role": "user", "owner": "bob", "text": instruction},
                {"role": "assistant", "text": "合成证据引用：" + secret},
            ],
        )
        self.call(
            self.a,
            "PUT",
            memory_path,
            {"text": secret, "scope": "private", "version": 2},
        )
        self.send(
            self.b,
            self.first,
            "shared",
            "after-withdrawal",
            "周末约会，刚才为什么改？",
            version=2,
        )
        context = self.provider.contexts[-1][1]
        self.assertNotIn(secret, json.dumps(context, ensure_ascii=False))
        self.assertFalse(context["conversation"])
        self.assertFalse(context["history"])

    def test_stale_module_request_is_removed_from_pending_after_partner_edit(self):
        key = "module-was-offline"
        self.provider.disabled = True
        self.send(self.a, self.first, "private", key, "改成书店", code=503)
        self.provider.disabled = False
        (pending,) = self.call(self.a, "GET", "state")["pending_messages"]
        self.assertEqual((pending["request_id"], pending["version"]), (key, 1))
        self.assertFalse(self.call(self.b, "GET", "state")["pending_messages"])
        self.call(
            self.b,
            "PUT",
            "modules/" + self.first["id"],
            {
                "version": 1,
                "title": "伴侣更新的活动",
                "body": "下午四点集合",
            },
        )
        self.assertFalse(self.call(self.a, "GET", "state")["pending_messages"])
        self.send(self.a, self.first, "private", key, "改成书店", code=409)
        self.send(
            self.a, self.first, "private", "module-new-version", "改成书店", version=2
        )
        self.assertFalse(self.call(self.a, "GET", "state")["pending_messages"])
        self.assertEqual(len(self.provider.contexts), 1)


class UpgradeTests(unittest.TestCase):
    def test_v1_schema_and_rows_survive_two_v2_opens(self):
        # Baseline SQL is identical to the deployed-branch commit 3af591d.
        self.assertEqual(
            hashlib.sha256(SCHEMA.encode()).hexdigest(),
            "00fb9bda769e210adb11f9f0c0013f7a646984c50107a21a89b43ec301acf89a",
        )
        directory = Path(self.enterContext(TemporaryDirectory()))
        key = Fernet.generate_key()
        (directory / "fixture-only.key").write_bytes(key)
        db = directory / "product.sqlite3"
        cfg = Settings(str(db), "alice", "bob", "fixture-only-channel", Fernet(key))
        up = FixtureUpstream(directory)
        token = up.login("a@example.test", "fixture-only")["token"]
        product_token = "v1" * 30
        scope, who, pair = "private", "alice", cfg.pair
        quote = "平日约会预算100元"
        items = encode([{"module": "date", "title": "旧计划", "body": "周末去公园"}])
        now = int(time.time())
        request = "v1-request"
        data = {
            "couples": (pair, cfg.channel, who, "bob", 10),
            "users": (pair, who, "Alice"),
            "sessions": (
                hashlib.sha256(product_token.encode()).hexdigest(),
                pair,
                who,
                cfg.encryption.encrypt(token.encode()),
                now + 3600,
            ),
            "profiles": (pair, who, 1, "{}", "{}"),
            "memories": ("memory", pair, who, scope, quote, 2, request),
            "chats": (
                pair,
                who,
                request,
                scope,
                quote,
                now,
                0,
                encode({"reply": "旧回答", "items": [], "memories": [quote]}),
                10,
                1,
                0,
                None,
                0,
            ),
            "drafts": ("draft", pair, who, scope, "confirmed", 2, items, request),
            "modules": (
                "module",
                pair,
                who,
                "date",
                "旧计划",
                "周末去公园",
                1,
                "draft",
                0,
            ),
            "feedback": (1, pair, who, scope, "draft", "date", "confirmed"),
            "usage": (1, pair, "2000-01-02", request, "returned", 11, 8),
        }
        columns = {}
        with sqlite3.connect(db) as c:
            c.executescript(SCHEMA)
            for table, row in data.items():
                columns[table] = ",".join(
                    r[1] for r in c.execute("PRAGMA table_info(" + table + ")")
                )
                marks = ",".join("?" for _ in row)
                c.execute(f"INSERT INTO {table} VALUES({marks})", row)
            c.execute("PRAGMA user_version=1")
        c.close()
        for _ in range(2):
            app, provider = fixture_app(directory)
            with TestClient(app) as client:
                response = client.get(
                    "/v1/state", headers={"Authorization": "Bearer " + product_token}
                )
                self.assertEqual(response.status_code, 200)
                restored = response.json()
                self.assertEqual(restored["modules"][0]["title"], "旧计划")
                self.assertEqual(restored["messages"]["private"][-1]["text"], "旧回答")
                self.assertEqual(restored["memories"][0]["text"], quote)
                self.assertEqual(restored["mandates"], [])
                self.assertFalse(provider.contexts)
            with sqlite3.connect(db) as c:
                self.assertEqual(c.execute("PRAGMA user_version").fetchone()[0], SCHEMA_VERSION)
                self.assertEqual(c.execute("PRAGMA foreign_key_check").fetchall(), [])
                for table, row in data.items():
                    self.assertEqual(
                        c.execute(f"SELECT {columns[table]} FROM {table}").fetchall(),
                        [row],
                        table,
                    )
                self.assertEqual(
                    c.execute("SELECT module_id,module_version FROM chats").fetchone(),
                    (None, None),
                )
                self.assertEqual(
                    c.execute("SELECT quote,at,origin FROM dp_evidence").fetchall(),
                    [(quote, now, request)],
                )
                self.assertGreater(
                    c.execute("SELECT COUNT(*) FROM dp_terms").fetchone()[0], 0
                )
            c.close()
