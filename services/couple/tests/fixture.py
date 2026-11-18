"""Isolated loopback integration fixture. Never contacts Open WebUI or a model."""

from contextlib import closing, contextmanager
from pathlib import Path
import argparse
import secrets
import sqlite3
import time
from threading import Lock
from tempfile import TemporaryDirectory

from cryptography.fernet import Fernet

from ..api import create_app
from ..database import Settings
from ..upstream import UpstreamError


class FixtureUpstream:
    def __init__(self, folder):
        self.path = str(Path(folder) / "synthetic-channel.sqlite3")
        self.contexts = []
        self.disabled = False
        self.bad_output = False
        self.fail_after_post = False
        self.forbidden = set()
        self.lock = Lock()
        with self.connection() as c:
            c.executescript("""CREATE TABLE IF NOT EXISTS session(t TEXT PRIMARY KEY, u TEXT);
                CREATE TABLE IF NOT EXISTS channel(id TEXT PRIMARY KEY,owner TEXT,text TEXT,role TEXT,created_at INTEGER);""")

    @contextmanager
    def connection(self):
        with closing(sqlite3.connect(self.path)) as con, con:
            yield con

    def login(self, email, password):
        uid = {
            "a@example.test": "alice",
            "b@example.test": "bob",
            "outsider@example.test": "outsider",
        }.get(email)
        if not uid or password != "fixture-only":
            raise UpstreamError("bad_credentials", "合成凭据无效", 401)
        token = secrets.token_urlsafe(32)
        with self.connection() as c:
            c.execute("INSERT INTO session VALUES(?,?)", (token, uid))
        return {"id": uid, "name": uid.capitalize(), "token": token}

    def uid(self, token):
        with self.connection() as c:
            row = c.execute("SELECT u FROM session WHERE t=?", (token,)).fetchone()
        if not row:
            raise UpstreamError("unauthorized", "请重新登录", 401)
        return row[0]

    def check_member(self, token, user_id):
        if self.uid(token) != user_id or user_id in self.forbidden:
            raise UpstreamError("not_member", "此账号无频道访问权限", 403)

    def signout(self, token):
        with self.connection() as c:
            c.execute("DELETE FROM session WHERE t=?", (token,))

    def channel_messages(self, token):
        self.uid(token)
        with self.connection() as c:
            c.row_factory = sqlite3.Row
            return [dict(r) for r in c.execute("SELECT * FROM channel ORDER BY rowid")]

    def channel_post(self, token, text, request_id, role="user"):
        owner = self.uid(token)
        with self.connection() as c:
            c.execute(
                "INSERT OR IGNORE INTO channel VALUES(?,?,?,?,?)",
                (request_id, owner, text, role, int(time.time())),
            )
        if self.fail_after_post:
            self.fail_after_post = False
            raise UpstreamError("delivery_unknown", "请刷新对账", 503)

    def complete(self, token, scope, text, context):
        self.uid(token)
        if self.disabled:
            raise UpstreamError("model_disabled", "测试模型已关闭", 503)
        with self.lock:
            self.contexts.append((scope, context))
        quiet = any(
            "人多" in m["text"] or "安静" in m["text"] for m in context["memories"]
        )
        items = []
        memories = []
        if "预算" in text or "周六" in text or "惊喜" in text:
            items = [
                {
                    "module": "date",
                    "title": "周末约会",
                    "body": "下午去安静的公园" if quiet else "下午一起出门",
                },
                {
                    "module": "calendar",
                    "title": "共同日程",
                    "body": "周六，预算 200 元",
                },
            ]
        elif "人多" in text:
            memories = ["我不喜欢人多"]
        if self.bad_output:
            items = [{"module": "outside", "title": "非法", "body": "非法"}]
        return {
            "reply": "【合成模型回执】" + ("选择安静场所" if quiet else "已收到"),
            "items": items,
            "memories": memories,
            "usage": {"prompt_tokens": 10, "completion_tokens": 12},
        }


def fixture_app(folder, daily=30):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    key = folder / "fixture-only.key"
    if not key.exists():
        key.write_bytes(Fernet.generate_key())
    settings = Settings(
        str(folder / "product.sqlite3"),
        "alice",
        "bob",
        "fixture-only-channel",
        Fernet(key.read_bytes()),
        daily,
        "fixture",
    )
    upstream = FixtureUpstream(folder)
    return create_app(settings, upstream), upstream


if __name__ == "__main__":
    import uvicorn

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18787)
    parser.add_argument(
        "--state-dir", type=Path, help="Separate directory for synthetic test records"
    )
    args = parser.parse_args()
    with TemporaryDirectory() as tmp:
        app, _ = fixture_app(args.state_dir or tmp)
        uvicorn.run(app, host="127.0.0.1", port=args.port, access_log=False)
