import base64
from contextlib import closing
import json
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from fastapi.testclient import TestClient

from .fixture import fixture_app
from .official_fixture import Provider, POSTER, POSTER_QUOTE, wav


class ApplicationToolsTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(
            patch(
                "services.couple.dp_tools.socket.getaddrinfo",
                return_value=[(2, 1, 0, "", ("93.184.216.34", 443))],
            )
        )
        self.folder = Path(self.enterContext(tempfile.TemporaryDirectory()))
        app, self.source = fixture_app(self.folder)
        self.client = self.enterContext(TestClient(app))
        self.a, self.b = (self.login(x) for x in ("a", "b"))
        self.source.tool_provider = self.provider = Provider()
        self.seq = 0
        self.db = app.state.db

    def login(self, user):
        response = self.client.post(
            "/v1/login",
            json={"email": user + "@example.test", "password": "fixture-only"},
        )
        response.raise_for_status()
        return {"Authorization": "Bearer " + response.json()["token"]}

    def call(self, method, path, who, body=None, code=200):
        res = self.client.request(method, "/v1/" + path, headers=who, json=body)
        self.assertEqual(res.status_code, code, res.text[:250])
        return res.json()

    def ask(self, kind, who=None, scope="private", text="", code=200, **kwargs):
        self.seq += 1
        form = {
            "kind": kind,
            "text": text,
            "scope": scope,
            "request_id": f"official-{self.seq:04}",
            **kwargs,
        }
        return self.call("POST", "ai/tools", who or self.a, form, code)

    def upload(self, name, mime, data, scope="private", **kwargs):
        return self.call(
            "POST",
            "ai/attachments",
            self.a,
            {
                "scope": scope,
                "name": name,
                "mime": mime,
                "data_b64": base64.b64encode(data).decode(),
                **kwargs,
            },
        )

    def test_public_tools_full_block_replay_sources_permissions_title_and_costs(self):
        first = self.ask(
            "web", text="冬季电影节", context={"date": "2026-11-18", "language": "中文"}
        )
        self.assertEqual(first["sources"][0]["url"], "https://example.com/festival")
        raw = json.loads(self.provider.requests[-1].content)
        self.assertEqual(raw["safety_check"], {"level": "high"})
        self.assertEqual(raw["max_tokens"], 1024)
        self.assertEqual(
            raw["messages"][0],
            {"role": "latest_reminder", "content": "2026-11-18, 中文"},
        )
        self.assertNotIn("history", first)
        self.assertNotIn("synthetic-signature", json.dumps(first))
        self.call("GET", "ai/tools/" + first["id"], self.b, code=404)
        self.ask("web", text="这条来源的活动是什么？", previous_id=first["id"])
        follow = json.loads(self.provider.requests[-1].content)
        self.assertEqual(
            follow["messages"][-2]["content"][1], self.provider.history_block
        )
        self.ask(
            "web", text="给我来源", previous_id=first["id"], scope="shared", code=404
        )
        shared = self.ask("image_search", text="公开电影节海报", scope="shared")
        self.assertEqual(
            self.call("GET", "ai/tools/" + shared["id"], self.b)["id"], shared["id"]
        )
        self.assertIn("图片", json.loads(self.provider.requests[-1].content)["system"])
        self.ask("deep_search", text="公开电影节信息")
        self.assertEqual(
            json.loads(self.provider.requests[-1].content)["thinking"],
            {"type": "enabled"},
        )
        self.ask("read_url", text="https://example.com/film")
        self.assertEqual(
            json.loads(self.provider.requests[-1].content)["tools"][0]["type"],
            "deepseek_read_url",
        )
        self.assertEqual(self.ask("title", text="一起看电影")["title"], "合成标题")
        for kind, text in (("search", "电影节"), ("fetch", "https://example.com/film")):
            answer = self.ask(kind, text=text)
            self.assertTrue(answer["sources"])
            self.assertEqual(answer["meter"][0]["estimated_cny"], "0.00500000")
        calls = len(self.provider.requests)
        self.ask("fetch", text="http://127.0.0.1/x", code=422)
        with patch(
            "services.couple.dp_tools.socket.getaddrinfo",
            return_value=[(2, 1, 0, "", ("10.0.1.100", 443))],
        ):
            self.ask("fetch", text="https://public-looking.example.org/path", code=422)
        self.assertEqual(len(self.provider.requests), calls)

    def test_poster_to_editable_draft_file_boundaries_revocation(self):
        file = self.upload("海报.png", "image/png", POSTER.read_bytes())
        self.ask("vision", self.b, text="读取日期", attachment_id=file["id"], code=404)
        self.ask(
            "vision",
            scope="shared",
            text="读取日期",
            attachment_id=file["id"],
            code=404,
        )
        self.ask("vision", text="读取日期", attachment_id=file["id"])
        self.assertEqual(
            json.loads(self.provider.requests[-1].content)["safety_check"]["level"],
            "high",
        )
        out = self.ask("poster_draft", text="生成约会草稿", attachment_id=file["id"])
        self.assertIn(POSTER_QUOTE, out["text"])
        self.assertEqual(self.call("GET", "state", self.b)["drafts"], [])
        self.assertEqual(self.call("GET", "state", self.a)["modules"], [])
        self.call("DELETE", "ai/attachments/" + file["id"], self.b, code=404)
        self.call("DELETE", "ai/attachments/" + file["id"], self.a)
        self.call("GET", "ai/tools/" + out["id"], self.a, code=404)
        draft = self.call("GET", "state", self.a)["drafts"][0]
        self.assertEqual(draft["status"], "cancelled")
        shared = self.upload("海报.png", "image/png", POSTER.read_bytes(), "shared")
        out = self.ask("poster_draft", scope="shared", attachment_id=shared["id"])
        draft = self.call("GET", "state", self.b)["drafts"][0]
        self.assertEqual(out["draft_id"], draft["id"])
        self.call(
            "POST",
            "drafts/" + draft["id"] + "/confirm",
            self.b,
            {"version": 1, "items": [dict(draft["items"][0], title="两人的电影夜")]},
        )
        self.assertEqual(
            self.call("GET", "state", self.a)["modules"][0]["title"], "两人的电影夜"
        )
        with self.db.connection(True) as c:
            c.execute("UPDATE tool_media SET expires=0 WHERE id=?", (shared["id"],))
        self.ask(
            "vision", text="读取", scope="shared", attachment_id=shared["id"], code=404
        )
        self.assertEqual(
            self.call("GET", "ai/tools?scope=shared", self.b)["results"], []
        )

    def test_office_pdf_ocr_asr_and_tts(self):
        pdf = self.upload("票根.pdf", "application/pdf", b"%PDF-1.5\nfixture")
        doc = self.upload(
            "节目.docx",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            b"PK\x03\x04fixture",
        )
        for file, kind, purpose in (
            (pdf, "parse_text", b"text_recognition"),
            (doc, "parse_rich", b"rich_layout_recognition"),
        ):
            res = self.ask(kind, attachment_id=file["id"])
            req, reason, delete = self.provider.requests[-3:]
            body = req.content
            self.assertLess(body.index(purpose), body.index(b"filename"))
            self.assertIn(b"expires_after[anchor]", body)
            self.assertIn(b"3600", body)
            self.assertEqual(delete.method, "DELETE")
            self.assertEqual(
                json.loads(reason.content)["messages"][-1]["content"][0]["source"][
                    "file_id"
                ],
                "file-api-synthetic-1",
            )
            self.assertEqual(res["meter"][0]["quantity"], 2)
            self.assertEqual(res["meter"][0]["estimated_cny"], "0.00300000")
        self.provider.no_pages = True
        self.assertIsNone(
            self.ask("parse_text", attachment_id=pdf["id"])["meter"][0]["quantity"]
        )
        read = self.ask("ocr", attachment_id=pdf["id"])
        self.assertIn(POSTER_QUOTE, read["text"])
        self.assertEqual(read["meter"][0]["unit"], "pages")
        sound = self.upload("voice.wav", "audio/wav", wav(), "shared")
        self.ask("asr", self.b, scope="shared", attachment_id=sound["id"], code=404)
        out = self.ask("asr", scope="shared", attachment_id=sound["id"])
        self.assertIn("发送前", out["text"])
        self.assertEqual(out["meter"][0]["quantity"], 4)
        self.assertEqual(self.call("GET", "state", self.b)["messages"]["shared"], [])
        self.call("GET", "ai/tools/" + out["id"], self.b, code=404)
        calls = len(self.provider.requests)
        self.ask("title", scope="shared", previous_id=out["id"], code=422)
        self.assertEqual(calls, len(self.provider.requests))
        spoken = self.ask("tts", scope="shared", previous_id=out["id"])
        self.call("GET", "ai/tools/" + spoken["id"], self.b, code=404)
        self.call("DELETE", "ai/attachments/" + sound["id"], self.a)
        self.call("GET", "ai/tools/" + spoken["id"], self.a, code=404)
        speak = self.ask("tts", text="你好 AI")
        self.assertEqual(speak["meter"][0]["quantity"], 7)
        self.assertEqual(base64.b64decode(speak["audio_b64"])[:4], b"RIFF")

    def test_abort_filter_unknown_outcome_and_quota(self):
        self.provider.broken = True
        self.ask("web", text="公开活动", request_id="retry-same-001", code=502)
        calls = len(self.provider.requests)
        self.ask("web", text="公开活动", request_id="retry-same-001", code=409)
        self.assertEqual(calls, len(self.provider.requests))
        self.provider.broken = False
        self.provider.refusal = True
        self.ask("web", text="测试安全结束", code=422)
        self.provider.refusal = False
        self.provider.input_blocked = True
        self.ask("web", text="测试输入拦截", code=422)
        self.assertEqual(
            self.call("GET", "ai/tools?scope=private", self.a)["results"], []
        )
        self.assertEqual(self.call("GET", "state", self.a)["drafts"], [])
        with (
            closing(sqlite3.connect(self.folder / "synthetic-gateway.sqlite")) as db,
            db,
        ):
            db.execute("UPDATE daily_budget SET used=30")
        self.provider.input_blocked = False
        calls = len(self.provider.requests)
        self.ask("search", text="样本", code=429)
        self.assertEqual(calls, len(self.provider.requests))
