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

    def official_tool(self, token, kind, payload):
        from .official_fixture import Provider, through_gateway

        self.uid(token)
        if self.disabled:
            raise UpstreamError("model_disabled", "合成工具已关闭", 503)
        with self.lock:
            if not hasattr(self, "tool_provider"):
                self.tool_provider = Provider()
            provider = self.tool_provider
        return through_gateway(Path(self.path).parent, provider, kind, payload)

    def generate_game(self, token, sources):
        self.uid(token)
        if self.disabled:
            raise UpstreamError("model_disabled", "合成模型已关闭", 503)
        with self.lock:
            self.contexts.append(("game", sources))
        source = sources[0]
        anchor = source["body"][:12]
        prompts = [
            "回想「%s」，你最想留下什么？",
            "再遇到「%s」，你想怎样记录？",
            "和对方聊起「%s」，你想先说什么？",
        ]
        options = [
            ["现场的声音", "当时的画面", "彼此的心情"],
            ["一起拍照", "写下几句", "留个纪念物"],
            ["最意外的事", "最开心的一刻", "下次的小愿望"],
        ]
        return {
            "questions": [
                {
                    "source_id": source["id"],
                    "anchor": anchor,
                    "prompt": q % anchor,
                    "options": opts,
                }
                for q, opts in zip(prompts, options)
            ],
            "usage": {"prompt_tokens": 11, "completion_tokens": 20},
        }

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
        reply = "选择安静场所" if quiet else "已收到"
        if context.get("mandates"):
            reply = "你们曾托付：" + context["mandates"][0]["task"]
        if context.get("activity_experiences"):
            experience = context["activity_experiences"][0]
            reply = f"参考 {experience['owner']} 的体验：{experience['text']}"
        if "看展" in text and "吃饭" in text:
            items = [
                {
                    "module": "date",
                    "title": "一起吃晚饭",
                    "body": "请两人分别确认晚饭意愿",
                },
                {"module": "date", "title": "可选看展", "body": "仅作为可选安排"},
            ]
        if (
            ("平日" in text or "生日" in text)
            and "预算" in text
            and not context.get("module_target")
        ):
            memories = [text]
        if "花销" in text or "依据" in text:
            budget = next(
                (m for m in context["memories"] if m.get("category") == "usual"), None
            )
            if budget:
                reply = f"{budget['owner']}：{budget['quote']}（记录时间 {budget['source_time']}）"
        if context.get("module_target"):
            target = context["module_target"][0]
            items = []
            memories = []
            if any(word in text for word in ("改", "调整", "修改")):
                items = [
                    {"module": target["module"], "title": target["title"], "body": text}
                ]
            reply = (
                "正在讨论「"
                + target["title"]
                + "」"
                + ("，已拟好修改草稿" if items else "")
            )
        purpose = (context.get("intent") or ["product"])[0]
        if purpose == "general":
            if "そうだ" in text and "ようだ" in text:
                reply = "传闻用「普通形＋そうだ」（雨が降るそうだ）；根据眼前线索推断可用「ようだ」（雨が降ったようだ）。另有表示看起来的「降りそうだ」。"
            elif "刚才" in text and "鼓励" in text:
                taught = any(
                    "ようだ" in turn["text"] and turn["role"] == "assistant"
                    for turn in context["conversation"]
                )
                reply = (
                    "少しずつ自信がついてきたようだね。応援しているよ。"
                    if taught
                    else "想用刚才哪个句型？"
                )
        elif purpose == "safety":
            reply = "你现在方便安全地说话吗？你可以先联系信任的人，由你决定下一步。"
        elif purpose == "relationship":
            if any(w in text for w in ("依恋", "截图", "回避型")):
                reply = "单凭截图无法判断对方的依恋类型。你想讨论截图里的哪件具体事情？"
            elif any(w in text for w in ("说重了", "道歉")):
                reply = "可以先私下拟一句：刚才我说重了，对不起。那件事对我仍然重要，我想等我们都准备好，再一起谈清楚。"
            elif any(w in text for w in ("好消息", "录取", "升职")):
                reply = "真为你高兴！这件好消息里，最让你开心的是哪一刻？"
            elif any(w in text for w in ("离开", "分手")):
                reply = "这个决定由你自己作主。如果需要，我们可以一起想想怎么表达边界。"
            else:
                reply = (
                    "可以分别说说自己的意思。两个人都愿意时才一起复盘，也可以随时退出。"
                )
        elif purpose == "choose_plan":
            reply = "请先打开你想修改的那一份计划。"
        if context.get("profile_mode") and purpose not in ("relationship", "safety"):
            cue = context["profile_mode"][0]["question"]
            reply = "谢谢你告诉我。" + cue["follow_up"]
        if self.bad_output:
            items = [{"module": "outside", "title": "非法", "body": "非法"}]
        return {
            "reply": "【合成模型回执】" + reply,
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
