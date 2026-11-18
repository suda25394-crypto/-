"""Nightly, owner-only portrait with distinct suggested and confirmed chat memories."""

import asyncio
import logging
import sqlite3
from contextlib import asynccontextmanager
from datetime import datetime, time, timedelta, timezone


# China's current civil day. This also works on Windows hosts without tzdata.
SHANGHAI = timezone(timedelta(hours=8), "Asia/Shanghai")
logger = logging.getLogger(__name__)

SQL_SCHEMA = """
CREATE TABLE IF NOT EXISTS portrait_sources(
    memory TEXT PRIMARY KEY REFERENCES memories(id) ON DELETE CASCADE,
    changed_at INTEGER NOT NULL, pending INTEGER NOT NULL DEFAULT 1,
    included_on TEXT, suppressed INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS portrait_pending ON portrait_sources(pending,changed_at);
CREATE TRIGGER IF NOT EXISTS portrait_on_candidate
AFTER INSERT ON memories
WHEN NEW.scope IN ('candidate','private','shared')
 AND EXISTS (SELECT 1 FROM chats WHERE pair=NEW.pair AND owner=NEW.owner
             AND request_id=NEW.source AND scope='private' AND done=1)
BEGIN
    INSERT INTO portrait_sources(memory,changed_at) VALUES(NEW.id,unixepoch());
END;
CREATE TRIGGER IF NOT EXISTS portrait_on_accept
AFTER UPDATE OF text,scope ON memories
WHEN NEW.scope IN ('private','shared')
 AND (NEW.scope != OLD.scope OR NEW.text != OLD.text)
 AND EXISTS (SELECT 1 FROM chats WHERE pair=NEW.pair AND owner=NEW.owner
             AND request_id=NEW.source AND scope='private' AND done=1)
BEGIN
    INSERT INTO portrait_sources(memory,changed_at) VALUES(NEW.id,unixepoch())
    ON CONFLICT(memory) DO UPDATE SET changed_at=excluded.changed_at,pending=1
    WHERE portrait_sources.suppressed=0;
END;
"""


def backfill(c):
    # Old rows have no memory timestamp. Carry forward only surviving private
    # chat pointers; historical suggestions retain their unconfirmed status.
    c.execute("""INSERT OR IGNORE INTO portrait_sources(memory,changed_at)
        SELECT m.id,h.at FROM memories m JOIN chats h
        ON h.pair=m.pair AND h.owner=m.owner AND h.request_id=m.source
        WHERE m.scope IN ('candidate','private','shared') AND h.scope='private' AND h.done=1""")


def forget_portrait(c, pair, owner):
    changed = c.execute(
        """UPDATE portrait_sources SET pending=0,included_on=NULL,suppressed=1
        WHERE suppressed=0 AND memory IN (SELECT id FROM memories WHERE pair=? AND owner=?)""",
        (pair, owner),
    )
    return changed.rowcount


def refresh_due(db, now=None):
    """Fold all outstanding changes from completed local days in one transaction."""
    now = now or datetime.now(SHANGHAI)
    day = now.astimezone(SHANGHAI).date()
    cutoff = int(datetime.combine(day, time.min, SHANGHAI).timestamp())
    with db.connection(True) as c:
        result = c.execute(
            """UPDATE portrait_sources SET pending=0,included_on=?
            WHERE pending=1 AND changed_at<? AND memory IN
            (SELECT id FROM memories WHERE pair=? AND scope IN ('candidate','private','shared'))""",
            (day.isoformat(), cutoff, db.settings.pair),
        )
        return result.rowcount


def for_owner(c, actor):
    rows = c.execute(
        """SELECT m.id,m.text,m.scope,s.included_on FROM portrait_sources s
        JOIN memories m ON m.id=s.memory WHERE m.pair=? AND m.owner=?
        AND m.scope IN ('candidate','private','shared') AND s.included_on IS NOT NULL
        ORDER BY s.included_on DESC,s.changed_at DESC,m.rowid DESC""",
        (actor.pair, actor.id),
    ).fetchall()
    if not rows:
        return None
    portrait = {"as_of": rows[0]["included_on"], "observations": [], "pending": []}
    for row in rows:
        section = "pending" if row["scope"] == "candidate" else "observations"
        portrait[section].append(
            {"id": row["id"], "text": row["text"], "source": "memory:" + row["id"]}
        )
    return portrait


@asynccontextmanager
async def scheduler(db):
    from .dp_tools import purge_expired

    async def attempt(job):
        try:
            await asyncio.to_thread(job, db)
            return True
        except sqlite3.OperationalError:
            logger.exception("Deferred local maintenance: %s", job.__name__)
            return False

    async def repeat(job, ok, delay):
        while True:
            await asyncio.sleep(delay() if ok else 60)
            ok = await attempt(job)

    def until_midnight():
        now = datetime.now(SHANGHAI)
        midnight = datetime.combine(now.date() + timedelta(days=1), time.min, SHANGHAI)
        return max(0, (midnight - now).total_seconds())

    # Catch up before serving the first projection. Attachments and portraits
    # have independent transactions and retry timers, even if only one fails.
    portrait_ok = await attempt(refresh_due)
    media_ok = await attempt(purge_expired)
    tasks = [
        asyncio.create_task(repeat(refresh_due, portrait_ok, until_midnight)),
        asyncio.create_task(repeat(purge_expired, media_ok, lambda: 3600)),
    ]
    try:
        yield
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
