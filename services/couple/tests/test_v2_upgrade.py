"""Round-trip a populated actual 0.3.0 DB into 0.4.0, entirely offline."""

import io
import json
from contextlib import closing
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import zipfile

from fastapi.testclient import TestClient


OLD_RELEASE = "7769b5c0475a1feb4dca85588e6dc25a7b2ad974"


def seed_older_release(package_root, storage):
    # This subprocess imports the pinned v2 product package before touching the DB.
    sys.path.insert(0, str(package_root))
    from services.couple.tests.fixture import fixture_app

    app, _ = fixture_app(storage)
    with TestClient(app) as client:

        def login(who):
            r = client.post(
                "/v1/login",
                json={"email": who + "@example.test", "password": "fixture-only"},
            )
            r.raise_for_status()
            return {"Authorization": "Bearer " + r.json()["token"]}

        a, b = login("a"), login("b")

        def call(method, path, who=a, **body):
            r = client.request(method, "/v1/" + path, headers=who, json=body or None)
            r.raise_for_status()
            return r.json()

        call(
            "POST",
            "messages",
            scope="private",
            request_id="migration-memory",
            text="我不喜欢人多",
        )
        mem = call("GET", "state")["memories"][0]
        call(
            "PUT",
            "memories/" + mem["id"],
            text="私人合成资料-雨伞",
            scope="private",
            version=1,
        )
        call(
            "POST",
            "messages",
            scope="shared",
            request_id="migration-group",
            text="下次一起去旧书摊",
        )
        msg = call("GET", "state")["messages"]["shared"][-1]
        call(
            "POST",
            "mandates",
            b,
            source_id=msg["id"],
            source_text=msg["text"],
            task="去旧书摊",
            cue="挑书",
        )
        for kind, title, body in (
            ("date", "旧版计划", "傍晚到书摊"),
            ("memory", "旧版回忆", "我们一起挑了两本旧书。"),
        ):
            call(
                "POST",
                "modules",
                confirmed=True,
                request_id="migration-" + kind,
                module=kind,
                title=title,
                body=body,
            )
        records = {r["module"]: r["id"] for r in call("GET", "state")["modules"]}
        path = "modules/" + records["date"] + "/"
        rev = {"proposal_version": 1, "version": 0}
        call("PUT", path + "vote", choice="accept", **rev)
        call("PUT", path + "vote", b, choice="decline", note="另选一天", **rev)
        call("PUT", path + "steps/happened", enabled=True, **rev)
        call("PUT", path + "review", scope="private", text="私人合成反馈-河边", **rev)
        call(
            "POST",
            path + "conversation",
            version=1,
            scope="private",
            request_id="migration-chat",
            text="把集合点改到街角",
        )
        game = call(
            "POST", "games", request_id="migration-game", source_ids=[records["memory"]]
        )
        call(
            "PUT",
            "games/" + game["id"] + "/choices",
            choices=[2, None, None],
            version=0,
        )
        # Temp files contain only disposable fixture credentials and disappear at test teardown.
        (storage / "before.json").write_text(
            json.dumps([[a, call("GET", "state", a)], [b, call("GET", "state", b)]]),
            encoding="utf-8",
        )


def snapshot(connection, columns=None):
    if columns is None:
        tables = [
            r[0]
            for r in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
        ]
        columns = {
            t: [r[1] for r in connection.execute("PRAGMA table_info(" + t + ")")]
            for t in tables
        }
    data = {
        t: connection.execute(
            "SELECT " + ",".join(cols) + " FROM " + t + " ORDER BY rowid"
        ).fetchall()
        for t, cols in columns.items()
    }
    return columns, data


class ReleaseUpgradeTests(unittest.TestCase):
    def test_actual_v2_api_records_survive_migration_and_second_open(self):
        from .fixture import fixture_app

        git = shutil.which("git")
        root = Path(__file__).resolve().parents[3]
        if not git or not (root / ".git").exists():
            self.skipTest(
                "An offline Git checkout with the 0.3.0 source object is required"
            )
        find = subprocess.run(
            [git, "cat-file", "-e", OLD_RELEASE + "^{commit}"],
            cwd=root,
            capture_output=True,
        )
        if find.returncode:
            self.skipTest(
                "Shallow checkout does not contain the pinned 0.3.0 source object"
            )
        folder = Path(self.enterContext(tempfile.TemporaryDirectory()))
        old = folder / "v2"
        storage = folder / "store"
        blob = subprocess.check_output(
            [git, "archive", "--format=zip", OLD_RELEASE, "services"], cwd=root
        )
        with zipfile.ZipFile(io.BytesIO(blob)) as z:
            z.extractall(old)
        subprocess.run(
            [
                sys.executable,
                str(Path(__file__).resolve()),
                "--seed",
                str(old),
                str(storage),
            ],
            check=True,
            capture_output=False,
        )
        sessions = json.loads((storage / "before.json").read_text(encoding="utf-8"))
        database = storage / "product.sqlite3"
        with closing(sqlite3.connect(database)) as c:
            self.assertEqual(c.execute("PRAGMA user_version").fetchone(), (2,))
            cols, data = snapshot(c)
            self.assertNotIn("intent", cols["chats"])
            for table in (
                "sessions",
                "dp_evidence",
                "dp_terms",
                "dp_targets",
                "activity_votes",
                "activity_steps",
                "activity_reviews",
                "dp_mandates",
                "dp_game_requests",
                "dp_games",
                "dp_game_turns",
            ):
                self.assertTrue(data[table], table)
        for _ in range(2):
            app, model = fixture_app(storage)
            with TestClient(app) as client:
                for headers, old_state in sessions:
                    res = client.get("/v1/state", headers=headers)
                    self.assertEqual(res.status_code, 200)
                    state = res.json()
                    for key in (
                        "profiles",
                        "memories",
                        "drafts",
                        "modules",
                        "activities",
                        "mandates",
                        "games",
                        "messages",
                    ):
                        self.assertEqual(state[key], old_state[key], key)
                self.assertFalse(model.contexts)
            with closing(sqlite3.connect(database)) as c:
                self.assertEqual(c.execute("PRAGMA user_version").fetchone(), (3,))
                self.assertEqual(snapshot(c, cols)[1], data)
                self.assertEqual(c.execute("PRAGMA foreign_key_check").fetchall(), [])


if __name__ == "__main__" and len(sys.argv) == 4 and sys.argv[1] == "--seed":
    seed_older_release(Path(sys.argv[2]), Path(sys.argv[3]))
