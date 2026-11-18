from concurrent.futures import ThreadPoolExecutor
from tempfile import TemporaryDirectory
import unittest

from fastapi.testclient import TestClient

from .fixture import fixture_app


class PairActivitiesR2Tests(unittest.TestCase):
    def test_two_people_reopen_notes_and_draws_on_unchanged_r2(self):
        with TemporaryDirectory() as folder:
            def start():
                app, source = fixture_app(folder)
                return TestClient(app), source

            def login(client, account):
                result = client.post("/v1/login", json={
                    "email": account + "@example.test", "password": "fixture-only",
                })
                self.assertEqual(result.status_code, 200, result.text)
                return {"Authorization": "Bearer " + result.json()["token"]}

            def state(client, who):
                result = client.get("/v1/state", headers=who)
                self.assertEqual(result.status_code, 200, result.text)
                return result.json()

            def vote(client, who, record, choice, note="", version=0):
                return client.put("/v1/modules/" + record["id"] + "/vote",
                                  headers=who, json={
                    "proposal_version": record["version"], "version": version,
                    "choice": choice, "note": note,
                })

            client, upstream = start()
            with client:
                a, b = login(client, "a"), login(client, "b")
                for record in [
                    {"module": "memory", "title": "便签 · 今天见", "body": "双人便签\n今天见", "request_id": "activity-note-1"},
                    {"module": "wish", "title": "交换向导", "body": "约会行动签\n轮流带路", "request_id": "activity-draw-1"},
                ]:
                    for _ in range(2):
                        res = client.post("/v1/modules", headers=a, json={**record,"confirmed":True})
                        self.assertEqual(res.status_code, 200, res.text)
                snapshot = state(client, b)
                self.assertEqual(len(snapshot["modules"]), 2)
                note, = [r for r in snapshot["modules"] if r["module"] == "memory"]
                draw, = [r for r in snapshot["modules"] if r["module"] == "wish"]
                # Response IDs are derived from each session, not supplied by the UI.
                with ThreadPoolExecutor(max_workers=2) as pool:
                    results = list(pool.map(lambda actor: vote(client, actor, draw, "accept"), (a, b)))
                self.assertEqual([r.status_code for r in results], [200, 200])
                for _ in range(2):
                    self.assertEqual(vote(client, b, note, "accept", "我来接你").status_code, 200)
                self.assertEqual(vote(client, b, note, "accept", "旧页面的草稿").status_code, 409)
                self.assertEqual(upstream.contexts, [])

            client, upstream = start()
            with client:
                a, b = login(client, "a"), login(client, "b")
                for actor in (a, b):
                    snapshot = state(client, actor)
                    acts = {r["module_id"]:r for r in snapshot["activities"]}
                    self.assertTrue(acts[draw["id"]]["agreed"])
                    receiver, = [v for v in acts[note["id"]]["votes"] if v["choice"] == "accept"]
                    self.assertEqual((receiver["owner"],receiver["note"],receiver["version"]),
                                     ("bob","我来接你",1))
                    self.assertEqual(len(snapshot["modules"]), 2)
                self.assertEqual(upstream.contexts, [])

                def advance(actor, key, action, op_id, **fields):
                    snapshot = state(client, actor)
                    version = next(r["version"] for r in snapshot["modules"] if r["id"] == key)
                    response = client.post(f"/v1/modules/{key}/life/{action}", headers=actor,
                                           json={"version":version,"request_id":op_id,**fields})
                    self.assertEqual(response.status_code, 200, response.text)
                    return response.json()["module_id"]

                def journey(actor):
                    return next(j for j in state(client, actor)["journeys"] if j["wish"] == draw["id"])

                meeting = {"day":"2026-11-19","clock":"14:30","place":"东门"}
                plan = advance(a, draw["id"], "meeting", "first-meeting", **meeting)
                for actor in (a, b):
                    j = journey(actor)
                    self.assertEqual((j["stage"],j["plan"],j["place"]), ("planned",plan,"东门"))
                    votes = next(v for v in state(client, actor)["activities"] if v["module_id"] == draw["id"])
                    self.assertFalse(votes["agreed"])
                advance(b, plan, "return", "return-to-wish")
                self.assertEqual(journey(a)["stage"], "wish")
                self.assertEqual(advance(b, draw["id"], "meeting", "second-meeting", **meeting), plan)
                memory = advance(a, plan, "remember", "remembering", occurred=True, note="一起到了东门")
                for actor in (a, b):
                    j = journey(actor)
                    self.assertEqual((j["stage"],j["memory"]), ("remembered",memory))
                self.assertEqual(upstream.contexts, [])
