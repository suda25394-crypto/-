"""D-47 using two authenticated sessions, persistent SQLite, and zero model calls."""

import base64
from concurrent.futures import ThreadPoolExecutor
import json
import struct
import unittest
from unittest.mock import patch
from uuid import uuid4
import zlib

from fastapi.testclient import TestClient

from . import test_product as product
from .fixture import fixture_app

DAY = "2026-11-18"


def tiny_png():
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))

    data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(b"\0\x10\x40\xaa\xff"))
        + chunk(b"IEND", b"")
    )
    return base64.b64encode(data).decode()


class DailyLifeTests(unittest.TestCase):
    setUp = product.ProductTests.setUp
    login = product.ProductTests.login
    call = product.ProductTests.call
    state = product.ProductTests.state

    def make(self, kind, title, body):
        self.call(
            "POST",
            "modules",
            self.a,
            {
                "request_id": uuid4().hex,
                "module": kind,
                "title": title,
                "body": body,
                "confirmed": True,
            },
        )
        return next(
            x["id"] for x in self.state(self.a)["modules"] if x["title"] == title
        )

    def v(self, key):
        return next(
            m["version"] for m in self.state(self.a)["modules"] if m["id"] == key
        )

    def payload(self, key, **data):
        return {"version": self.v(key), "request_id": uuid4().hex, **data}

    def post(self, key, act, body, actor=None, status=200):
        return self.call(
            "POST", f"modules/{key}/life/{act}", actor or self.a, body, status
        )

    def vote(self, key, who):
        self.call(
            "PUT",
            f"modules/{key}/vote",
            who,
            {"choice": "accept", "proposal_version": self.v(key), "version": 0},
        )

    def test_confirmed_dp_update_changes_same_meeting_once_from_final_draft(self):
        with patch("services.couple.daily_life.today", return_value=DAY):
            key = self.make("calendar", "海风散步", "湖边散步")
            self.post(
                key,
                "meeting",
                self.payload(key, day=DAY, clock="17:30", place="东门", address=""),
            )
            self.vote(key, self.a)
            self.vote(key, self.b)

            def draft(text, module=False):
                data = {"request_id": uuid4().hex, "scope": "private", "text": text}
                path = "messages"
                if module:
                    path = f"modules/{key}/conversation"
                    data["version"] = self.v(key)
                self.call(
                    "POST",
                    path,
                    self.a,
                    data,
                )
                d = next(
                    x for x in self.state(self.a)["drafts"] if x["status"] == "pending"
                )
                self.assertEqual(d["target_id"], key)
                return d

            def confirm(d, body, code=200):
                args = {
                    "version": d["version"],
                    "items": [dict(d["items"][0], body=body)],
                }
                self.call("POST", "drafts/" + d["id"] + "/confirm", self.a, args, code)

            def latest():
                return self.state(self.b)["today_plans"][0]

            d = draft("把我们确认好的周末计划改成下午四点")
            self.assertEqual(latest()["clock"], "17:30")
            for invalid in (
                "集合时间：15:30\n集合时间：16:00",
                "集合时间：25:97",
                "集合时间：下午四十时",
                "集合时间：16:",
            ):
                confirm(d, invalid, 422)
            self.assertEqual((latest()["clock"], latest()["version"]), ("17:30", 2))
            confirm(d, "周末改为下午四点一起去海边")
            confirm(d, "周末改为下午四点一起去海边")
            self.assertEqual(
                (latest()["clock"], latest()["version"], latest()["place"]),
                ("16:00", 3, "东门"),
            )
            events = self.state(self.b)["joint_changes"]
            matching = [
                e for e in events if e["module_id"] == key and e["version"] == 3
            ]
            self.assertEqual(len(matching), 1)
            self.assertEqual(matching[0]["actor"], "alice")
            self.assertEqual(matching[0]["current"]["clock"], "16:00")
            self.assertEqual(matching[0]["previous"], {"clock": "17:30"})
            self.assertFalse(latest()["agreed_current"])
            d = draft("把我们确认好的周末计划改成下午四点")
            confirm(d, "下午看电影，四点散场")
            self.assertEqual((latest()["clock"], latest()["version"]), ("16:00", 4))
            named = "把海风散步的周末计划改为下午四点半"
            final = "周末改为下午四点半一起去海边"
            d = draft(named)
            confirm(d, final)
            self.assertEqual((latest()["clock"], latest()["version"]), ("16:30", 5))
            # An earlier service saved this final body with a stale structured field.
            self.post(
                key,
                "meeting",
                self.payload(key, day=DAY, clock="16:00", place="东门", address=""),
            )
            d = draft(named)
            confirm(d, final)
            self.assertEqual((latest()["clock"], latest()["version"]), ("16:30", 7))
            d = draft("把集合时间改为下午", module=True)
            confirm(d, "周末下午见面")
            self.assertEqual((latest()["clock"], latest()["version"]), ("", 8))

    def test_latest_meeting_feed_read_receipt_does_not_vote_and_survives_restart(self):
        with patch("services.couple.daily_life.today", return_value=DAY):
            key = self.make("calendar", "去看海", "两个人的约会")
            south = {
                "day": DAY,
                "clock": "14:30",
                "place": "南门",
                "address": "海州市滨海公园",
            }
            self.post(key, "meeting", self.payload(key, **south))
            self.assertFalse(self.state(self.b)["today_plans"])
            self.vote(key, self.a)
            self.assertFalse(self.state(self.b)["today_plans"])
            self.vote(key, self.b)
            self.assertTrue(self.state(self.b)["today_plans"][0]["agreed_current"])
            east = dict(south, place="东门")
            update = self.payload(key, **east)
            self.post(key, "meeting", update)
            self.post(key, "meeting", update)
            self.post(key, "meeting", update | {"place": "外门"}, status=409)
            b = self.state(self.b)
            row = b["joint_changes"][0]
            self.assertEqual(
                (
                    row["module_id"],
                    row["actor"],
                    row["author"],
                    row["previous"],
                    row["current"],
                    row["seen"],
                ),
                (key, "alice", "Alice", {"place": "南门"}, {"place": "东门"}, False),
            )
            self.assertEqual(
                (b["today_plans"][0]["place"], b["today_plans"][0]["agreed_current"]),
                ("东门", False),
            )
            for _ in range(2):
                self.call("PUT", f"life/changes/{row['id']}/read", self.b)
            self.call("PUT", f"life/changes/{row['id']}/read", self.a, code=404)
            self.call("GET", "life/changes", {}, code=401)
            app, _ = fixture_app(self.folder.name)
            with TestClient(app) as reopened:
                state = reopened.get("/v1/state", headers=self.b).json()
                self.assertTrue(state["joint_changes"][0]["seen"])
                self.assertTrue(
                    all(v["choice"] is None for v in state["activities"][0]["votes"])
                )
                self.assertEqual(state["today_plans"][0]["version"], 3)
            self.post(
                key,
                "meeting",
                self.payload(key, day=DAY, place="", clock="", address=""),
            )
            current = self.state(self.b)
            self.assertFalse(current["today_plans"][0]["address"])
            self.assertNotIn(
                "南门", json.dumps(current["joint_changes"], ensure_ascii=False)
            )
            self.assertNotIn(
                "东门", json.dumps(current["joint_changes"], ensure_ascii=False)
            )
            self.assertEqual(self.source.contexts, [])

    def test_wish_reschedule_return_reuse_plan_and_memory_without_duplicates(self):
        wish = self.make("wish", "想一起去海边", "雨天就等等")
        form = self.payload(wish, day=DAY, clock="16:00")
        with ThreadPoolExecutor(max_workers=2) as pool:
            ids = [
                f.result()["module_id"]
                for f in [
                    pool.submit(self.post, wish, "meeting", form) for _ in range(2)
                ]
            ]
        self.assertEqual(ids[0], ids[1])
        plan = ids[0]
        self.post(
            plan, "meeting", self.payload(plan, day="2026-11-20", clock="17:30"), self.b
        )
        back = self.payload(plan)
        self.assertEqual(self.post(plan, "return", back, self.b)["module_id"], wish)
        self.assertEqual(self.post(plan, "return", back, self.b)["module_id"], wish)
        self.assertEqual(self.state(self.a)["journeys"][0]["stage"], "wish")
        self.post(
            plan,
            "remember",
            self.payload(plan, occurred=True, note="还没出发"),
            status=409,
        )
        self.assertEqual(
            self.post(
                wish, "meeting", self.payload(wish, day="2026-11-21", clock="10:30")
            )["module_id"],
            plan,
        )
        remember = self.payload(
            plan, occurred=True, note="海风很凉，我们一直走到日落。"
        )
        memory = self.post(plan, "remember", remember)["module_id"]
        self.assertEqual(self.post(plan, "remember", remember)["module_id"], memory)
        self.post(
            plan,
            "remember",
            self.payload(plan, occurred=True, note="再次成行"),
            self.b,
            status=409,
        )
        for person in (self.a, self.b):
            result = self.state(person)
            self.assertEqual(len(result["modules"]), 3)
            chain = result["journeys"][0]
            self.assertEqual(
                (chain["wish"], chain["plan"], chain["memory"], chain["stage"]),
                (wish, plan, memory, "remembered"),
            )
            self.assertEqual(
                next(x for x in result["modules"] if x["id"] == memory)["body"],
                remember["note"],
            )
        self.assertTrue(
            next(x for x in self.state(self.a)["activities"] if x["module_id"] == plan)[
                "steps"
            ]["happened"]["at"]
        )
        self.assertNotIn(
            "happened",
            next(x for x in self.state(self.b)["activities"] if x["module_id"] == plan)[
                "steps"
            ],
        )
        self.assertEqual(self.source.contexts, [])

    def test_photo_permission_and_withdrawal_and_no_partial_record_on_invalid_input(
        self,
    ):
        key = self.make("date", "回忆照片", "沙滩")
        self.post(
            key,
            "remember",
            self.payload(key, occurred=False, note="未参加"),
            status=422,
        )
        self.post(
            key,
            "remember",
            self.payload(key, occurred=True, photo="c2VjcmV0"),
            status=422,
        )
        self.assertEqual(len(self.state(self.a)["modules"]), 1)
        img = tiny_png()
        memory = self.post(
            key, "remember", self.payload(key, occurred=True, photo=img)
        )["module_id"]
        self.assertNotIn(img, json.dumps(self.state(self.a)))
        path = f"modules/{memory}/life/photo"
        self.assertEqual(self.call("GET", path, self.b)["png"], img)
        self.call("GET", path, {}, code=401)
        self.call("DELETE", path, self.b, code=404)
        self.call("DELETE", path, self.a)
        self.call("GET", path, self.b, code=404)
        self.assertEqual(self.state(self.b)["memory_photos"], [])

    def test_general_editor_private_draft_filter_and_stale_meeting_version(self):
        key = self.make("calendar", "野餐", "在南门")
        self.call(
            "PUT",
            f"modules/{key}",
            self.a,
            {"version": 1, "title": "野餐", "body": "在东门"},
        )
        row = self.state(self.b)["joint_changes"][0]
        self.assertEqual(
            (row["action"], row["fields"], row["current"]),
            ("edit", ["body"], {"body": "在东门"}),
        )
        target = self.payload(key, day=DAY, address="待定", place="东门")
        self.post(key, "meeting", target, status=422)
        self.post(key, "meeting", dict(target, version=1, address=""), status=409)
        self.call(
            "POST",
            f"modules/{key}/conversation",
            self.a,
            {
                "version": 2,
                "scope": "private",
                "text": "秘密：把地点改到画室",
                "request_id": uuid4().hex,
            },
        )
        self.assertNotIn(
            "画室", json.dumps(self.state(self.b)["joint_changes"], ensure_ascii=False)
        )
        self.assertEqual(len(self.state(self.b)["joint_changes"]), 1)
