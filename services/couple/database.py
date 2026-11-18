"""SQLite transaction boundary; one configured household per pair namespace."""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from cryptography.fernet import Fernet

SCHEMA_VERSION = 2
SCHEMA = """
CREATE TABLE IF NOT EXISTS couples (
    id TEXT PRIMARY KEY, channel TEXT NOT NULL, a TEXT NOT NULL, b TEXT NOT NULL,
    epoch INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS users (
    pair TEXT NOT NULL REFERENCES couples, id TEXT NOT NULL, name TEXT NOT NULL,
    PRIMARY KEY(pair,id)
);
CREATE TABLE IF NOT EXISTS sessions (
    digest TEXT PRIMARY KEY, pair TEXT NOT NULL REFERENCES couples, owner TEXT NOT NULL,
    upstream BLOB NOT NULL, expires INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS profiles (
    pair TEXT NOT NULL REFERENCES couples, owner TEXT NOT NULL, version INTEGER NOT NULL,
    draft TEXT NOT NULL, released TEXT, PRIMARY KEY(pair,owner)
);
CREATE TABLE IF NOT EXISTS memories (
    id TEXT PRIMARY KEY, pair TEXT NOT NULL REFERENCES couples, owner TEXT NOT NULL,
    scope TEXT NOT NULL, text TEXT NOT NULL, version INTEGER NOT NULL, source TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS drafts (
    id TEXT PRIMARY KEY, pair TEXT NOT NULL REFERENCES couples, owner TEXT NOT NULL,
    scope TEXT NOT NULL, status TEXT NOT NULL, version INTEGER NOT NULL,
    items TEXT NOT NULL, source TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS modules (
    id TEXT PRIMARY KEY, pair TEXT NOT NULL REFERENCES couples, owner TEXT NOT NULL,
    module TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, version INTEGER NOT NULL,
    draft TEXT NOT NULL REFERENCES drafts, ordinal INTEGER NOT NULL, UNIQUE(draft,ordinal)
);
CREATE TABLE IF NOT EXISTS chats (
    pair TEXT NOT NULL REFERENCES couples, owner TEXT NOT NULL, request_id TEXT NOT NULL,
    scope TEXT NOT NULL, input TEXT NOT NULL, at INTEGER NOT NULL,
    posted INTEGER NOT NULL DEFAULT 0, output TEXT, epoch INTEGER,
    done INTEGER NOT NULL DEFAULT 0, busy_until INTEGER NOT NULL DEFAULT 0,
    lease TEXT, uncertain INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(pair,owner,request_id)
);
CREATE TABLE IF NOT EXISTS feedback (
    id INTEGER PRIMARY KEY, pair TEXT NOT NULL REFERENCES couples, owner TEXT NOT NULL,
    scope TEXT NOT NULL, draft TEXT NOT NULL REFERENCES drafts, module TEXT NOT NULL,
    action TEXT NOT NULL, UNIQUE(draft,module)
);
CREATE TABLE IF NOT EXISTS usage (
    id INTEGER PRIMARY KEY, pair TEXT NOT NULL REFERENCES couples, day TEXT NOT NULL,
    request_id TEXT NOT NULL, outcome TEXT NOT NULL, in_tokens INTEGER, out_tokens INTEGER
);
CREATE INDEX IF NOT EXISTS usage_day ON usage(pair,day);
CREATE INDEX IF NOT EXISTS chats_scope ON chats(pair,scope,owner,at);
"""


@dataclass(frozen=True)
class Settings:
    path: str
    a: str
    b: str
    channel: str
    encryption: Fernet
    daily: int = 30
    mode: str = "live"

    def __post_init__(self):
        if not self.a or not self.b or not self.channel or self.a == self.b:
            raise ValueError("Configure two distinct account IDs and a channel")
        if not 1 <= self.daily <= 30:
            raise ValueError("DEMO_DAILY_REQUESTS must be between 1 and 30")

    @property
    def pair(self):
        # An account reassignment must not expose the previous household's rows.
        return hashlib.sha256(
            encode([self.channel, *sorted([self.a, self.b])]).encode()
        ).hexdigest()

    @classmethod
    def environment(cls):
        key = Path(os.environ["COUPLE_SESSION_KEY_FILE"]).read_bytes().strip()
        return cls(
            os.environ["COUPLE_DB"],
            os.environ["COUPLE_USER_A_ID"],
            os.environ["COUPLE_USER_B_ID"],
            os.environ["COUPLE_CHANNEL_ID"],
            Fernet(key),
            int(os.getenv("DEMO_DAILY_REQUESTS", "30")),
        )


def encode(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":"))


class Database:
    def __init__(self, settings):
        self.settings = settings
        Path(settings.path).parent.mkdir(parents=True, exist_ok=True)
        with self.connection() as c:
            c.execute("PRAGMA journal_mode=WAL")
            version = c.execute("PRAGMA user_version").fetchone()[0]
            if version not in (0, 1, SCHEMA_VERSION):
                raise RuntimeError("Unsupported database schema version")
            from . import dp_activity, dp_mandates, dp_game, dp_recall

            c.executescript(
                "BEGIN IMMEDIATE;\n"
                + SCHEMA
                + dp_recall.SQL_SCHEMA
                + dp_activity.SQL_SCHEMA
                + dp_mandates.SQL_SCHEMA
                + dp_game.SQL_SCHEMA
            )
            columns = {r["name"] for r in c.execute("PRAGMA table_info(chats)")}
            for name, kind in (("module_id", "TEXT"), ("module_version", "INTEGER")):
                if name not in columns:
                    c.execute(f"ALTER TABLE chats ADD COLUMN {name} {kind}")
            c.execute(
                "CREATE INDEX IF NOT EXISTS chats_thread ON chats(pair,owner,module_id,at)"
            )
            if version < 2:
                dp_recall.backfill(c)
            c.execute(
                "INSERT OR IGNORE INTO couples(id,channel,a,b) VALUES(?,?,?,?)",
                (settings.pair, settings.channel, settings.a, settings.b),
            )
            c.execute(f"PRAGMA user_version={SCHEMA_VERSION}")
            c.commit()

    @contextmanager
    def connection(self, write=False):
        con = sqlite3.connect(self.settings.path, timeout=8, isolation_level=None)
        con.row_factory = sqlite3.Row
        con.execute("PRAGMA foreign_keys=ON")
        try:
            if write:
                con.execute("BEGIN IMMEDIATE")
            yield con
            if write:
                con.commit()
        except BaseException:
            con.rollback()
            raise
        finally:
            con.close()
