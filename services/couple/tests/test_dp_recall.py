"""Dated synthetic household with two separate sessions. No network/provider credentials."""

import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

import httpx
from fastapi.testclient import TestClient
from services.couple.database import encode
from services.couple.dp_recall import index_turn
from services.couple.upstream import BODY_LIMIT, Upstream, UpstreamConfig
from .fixture import fixture_app


class CrossMonthTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(self.enterContext(tempfile.TemporaryDirectory()))
        app, self.model = fixture_app(self.folder)
        self.http = self.enterContext(TestClient(app))
        self.a, self.b = (self.login(x) for x in ("a", "b"))
        self.db = app.state.db
        self.pair = self.db.settings.pair
        self.seq = 0

    def login(self, name):
        reply = self.http.post(
            "/v1/login",
            json={"email": name + "@example.test", "password": "fixture-only"},
        )
        reply.raise_for_status()
        return {"Authorization": "Bearer " + reply.json()["token"]}

    def call(self, actor, method, path, body=None):
        response = self.http.request(method, "/v1/" + path, headers=actor, json=body)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def say(self, who, text, scope="private"):
        self.seq += 1
        req = f"recall-topic-{self.seq:04}"
        self.call(who, "POST", "messages", dict(scope=scope, text=text, request_id=req))
        return req

    def consent(self, phrase, month, scope="private"):
        req = self.say(self.a, phrase)
        stamp = int(datetime(2026, month, 12, 10, 30, tzinfo=timezone.utc).timestamp())
        with self.db.connection(True) as c:
            c.execute(
                "UPDATE chats SET at=? WHERE pair=? AND owner='alice' AND request_id=?",
                (stamp, self.pair, req),
            )
        m = self.call(self.a, "GET", "state")["memories"][-1]
        self.call(
            self.a,
            "PUT",
            "memories/" + m["id"],
            dict(version=1, text=m["text"], scope=scope),
        )
        return m["id"], req, stamp

    def transport(self, ctx, text, scope="private"):
        # Exercise exactly the model adapter used by the live service; substitute only its network transport.
        captured = []

        def receive(req):
            if req.url.host == "web.test":
                return httpx.Response(200, json={"data": [{"id": "deepseek-flash"}]})
            captured.append(req.content)
            return httpx.Response(
                200,
                json={
                    "choices": [
                        {
                            "message": {
                                "content": encode(
                                    dict(reply="测试", items=[], memories=[])
                                )
                            }
                        }
                    ],
                    "usage": {"prompt_tokens": 10, "completion_tokens": 12},
                },
            )

        client = Upstream(
            UpstreamConfig(
                "http://web.test",
                "http://gateway.test",
                "test",
                frozenset({"alice", "bob"}),
                "f" * 32,
                str(self.folder / "ledger.sqlite"),
            ),
            httpx.MockTransport(receive),
        )
        client.complete("synthetic", scope, text, ctx)
        self.assertEqual(len(captured), 1)
        self.assertLessEqual(len(captured[0]), BODY_LIMIT)
        data = json.loads(json.loads(captured[0])["messages"][1]["content"])[
            "authorized_context"
        ]
        return data, len(captured[0])

    def test_cross_month_budget_correction_and_revocation(self):
        self.consent("我平日约会的预算是100元", 2)
        phrase = "把我的平日约会预算改为150元"
        memory, origin, stamp = self.consent(phrase, 6)
        self.consent("这次生日约会临时预算200元", 8)
        with self.db.connection(True) as c:
            for i in range(120):
                request = f"noise-entry-{i:04}"
                text = f"记录今天整理的蓝色纽扣编号{i}"
                c.execute(
                    """INSERT INTO chats(pair,owner,request_id,scope,input,at,epoch,done) VALUES(?,'alice',?,'private',?,?,3,1)""",
                    (self.pair, request, text, stamp + i * 86400),
                )
                index_turn(c, self.pair, "alice", request, text)
        question = "按平时的花销安排周末"
        self.say(self.a, question)
        ctx, size = self.transport(self.model.contexts[-1][1], question)
        evidence = ctx["memories"]
        self.assertEqual(
            [(r["quote"], r["owner"], r["source"], r["at"]) for r in evidence],
            [(phrase, "alice", origin, stamp)],
        )
        self.assertNotIn("200元", encode(ctx))
        self.assertNotIn("100元", encode(ctx))
        self.assertIn(
            "150元",
            self.call(self.a, "GET", "state")["messages"]["private"][-1]["text"],
        )
        self.say(self.a, "依据是哪句话？")
        cited, follow_size = self.transport(
            self.model.contexts[-1][1], "依据是哪句话？"
        )
        self.assertEqual(cited["memories"], evidence)
        self.assertIn(
            "2026-06-12T18:30+08:00",
            self.call(self.a, "GET", "state")["messages"]["private"][-1]["text"],
        )
        self.say(self.b, question)
        private, _ = self.transport(self.model.contexts[-1][1], question)
        self.assertNotIn("150元", encode(private))
        self.say(self.b, "@DP " + question, "shared")
        public, _ = self.transport(
            self.model.contexts[-1][1], "@DP " + question, "shared"
        )
        self.assertNotIn("150元", encode(public))
        self.call(self.a, "DELETE", "memories/" + memory + "?version=2")
        self.say(self.a, question)
        revoked, _ = self.transport(self.model.contexts[-1][1], question)
        self.assertFalse(revoked["memories"])
        self.assertNotIn("150元", encode(revoked))
        self.assertNotIn("100元", encode(revoked))
        print(
            f"Cross-month fixture: 120 unrelated turns; source={origin} at={stamp}; gateway body={size}/{follow_size} bytes; fixture prompt_tokens=10, provider calls=0"
        )

    def test_released_memory_does_not_publish_private_source_message(self):
        request = self.say(self.a, "我不喜欢人多，私人安排是蓝信封")
        m = self.call(self.a, "GET", "state")["memories"][0]
        path = "memories/" + m["id"]
        self.call(
            self.a, "PUT", path, dict(version=1, text="我不喜欢人多", scope="shared")
        )
        self.say(self.b, "@DP 周末想出去", "shared")
        ctx, _ = self.transport(self.model.contexts[-1][1], "@DP 周末想出去", "shared")
        self.assertEqual(ctx["memories"][0]["quote"], "我不喜欢人多")
        self.assertNotIn("蓝信封", encode(ctx))
        self.assertNotIn(request, encode(ctx))
        self.call(
            self.a, "PUT", path, dict(version=2, text="喜欢安静的公园", scope="private")
        )
        self.say(self.b, "@DP 周末想出去", "shared")
        self.assertFalse(self.model.contexts[-1][1]["memories"])
        self.say(self.a, "周末想出去")
        mine = self.model.contexts[-1][1]["memories"][0]
        self.assertEqual(
            (mine["quote"], mine["source"]),
            ("喜欢安静的公园", "memory-edit:" + m["id"]),
        )
