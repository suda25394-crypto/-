"""Owner-only guided chat. Questions are research-informed prompts, not scored items."""

import json
import re

from fastapi import Depends, Request
from pydantic import BaseModel, ConfigDict, Field

from . import daily_portrait
from .database import encode


MODE_SCHEMA = """
CREATE TABLE IF NOT EXISTS profile_focus (
    pair TEXT NOT NULL, owner TEXT NOT NULL, memory TEXT NOT NULL REFERENCES memories ON DELETE CASCADE,
    version INTEGER NOT NULL, PRIMARY KEY(pair,owner,memory)
);
CREATE TABLE IF NOT EXISTS profile_selections(
    pair TEXT NOT NULL, owner TEXT NOT NULL, through_turn INTEGER NOT NULL,
    PRIMARY KEY(pair,owner)
);
CREATE TABLE IF NOT EXISTS profile_modes (
    pair TEXT NOT NULL REFERENCES couples, owner TEXT NOT NULL,
    active INTEGER NOT NULL, topic INTEGER NOT NULL, version INTEGER NOT NULL,
    PRIMARY KEY(pair,owner)
);
CREATE TABLE IF NOT EXISTS profile_mode_turns (
    pair TEXT NOT NULL, owner TEXT NOT NULL, request_id TEXT NOT NULL,
    version INTEGER NOT NULL,
    PRIMARY KEY(pair,owner,request_id),
    FOREIGN KEY(pair,owner,request_id) REFERENCES chats(pair,owner,request_id)
);
"""


QUESTIONS = (
    {
        "id": "responsiveness",
        "theme": "被理解的时刻",
        "text": "最近哪一次，你觉得对方真的听懂了你？",
        "follow_up": "对方当时说了什么，或者做了什么？",
        "source": "Arican-Dinc & Gable (2023) · 伴侣回应性",
        "doi": "10.1016/j.copsyc.2023.101652",
    },
    {
        "id": "good_news",
        "theme": "分享好消息",
        "text": "遇到一件特别开心的小事，你喜欢对方怎么接你的话？",
        "follow_up": "有什么回应，会让你想把这件开心的事多讲一点？",
        "source": "Gable 等 (2004) · 分享积极事件",
        "doi": "10.1037/0022-3514.87.2.228",
    },
    {
        "id": "shared_novelty",
        "theme": "一起尝试新事物",
        "text": "最近有没有什么小事，你愿意和对方一起试一试？",
        "follow_up": "怎样一起尝试，会让你觉得更自在或更有趣？",
        "source": "Aron 等 (2000) · 共同参与新活动",
        "doi": "10.1037/0022-3514.78.2.273",
    },
)

MODE_INSTRUCTION = """
仅当服务端 authorized_context.profile_mode 非空时，表示本人在自己的私聊中主动选择了「让 DP 了解我」。下段指引仅在此时适用；未开启时正常回应，不追问档案。
当前话题、研究来源和已问问题见 profile_mode。
所列问题是依据研究构念自拟的聊天引导。先回应本人原话。需要继续时可围绕给定 follow_up 联系刚提到的经历，
每次最多追问一件事，已答过就自然收住。征询是否记住或怎样表述由本人决定。
开场问题已经显示，不要逐字重问，不要连问、给选项、打分或判定依恋类型。不要编造题目依据或声称这是验证过的量表。
用户转话题时直接回应新需求，表达不想聊时尊重并停止追问。
只把当事人清楚表达的持续偏好列为待本人确认的 memories 候选；一次心情、伴侣的猜测和未获认可的推断不要写入。
"""


def _row(c, actor):
    return c.execute(
        "SELECT active,topic,version FROM profile_modes WHERE pair=? AND owner=?",
        (actor.pair, actor.id),
    ).fetchone()


def mode_state(c, actor):
    row = _row(c, actor)
    active = bool(row and row["active"])
    return {
        "active": active,
        "version": row["version"] if row else 0,
        "question": QUESTIONS[row["topic"]] if active else None,
        "answered": bool(
            active
            and c.execute(
                """SELECT 1 FROM profile_mode_turns t JOIN chats h
            USING(pair,owner,request_id) WHERE t.pair=? AND t.owner=? AND t.version=? AND h.done=1
            LIMIT 1""",
                (actor.pair, actor.id, row["version"]),
            ).fetchone()
        ),
    }


def change_mode(c, actor, action, expected):
    # Database imports MODE_SCHEMA while initializing, so business is loaded only on request.
    from .business import Failure, check_version, bump_epoch

    row = _row(c, actor)
    version = row["version"] if row else 0
    check_version(version, expected)
    active = bool(row and row["active"])
    topic = row["topic"] if row else -1
    if (action == "start" and active) or (action == "end" and not active):
        return mode_state(c, actor)
    if action == "skip" and not active:
        raise Failure(409, "mode_inactive", "请先开启「让 DP 了解我」。")
    if action == "start":
        previous = c.execute(
            """SELECT input FROM chats WHERE pair=? AND owner=? AND scope='private'
            AND module_id IS NULL AND done=1 ORDER BY at DESC,rowid DESC LIMIT 1""",
            (actor.pair, actor.id),
        ).fetchone()
        text = previous["input"] if previous else ""
        if re.search(r"开心|好消息|喜讯|庆祝|获奖", text):
            topic = 1
        elif re.search(r"出游|旅行|第一次|周末|海边|安排|看展", text):
            topic = 2
        else:
            topic = (topic + 1) % len(QUESTIONS)
    elif action == "skip":
        topic = (topic + 1) % len(QUESTIONS)
    c.execute(
        "DELETE FROM profile_focus WHERE pair=? AND owner=?", (actor.pair, actor.id)
    )
    c.execute(
        """INSERT INTO profile_modes(pair,owner,active,topic,version) VALUES(?,?,?,?,?)
           ON CONFLICT(pair,owner) DO UPDATE SET active=excluded.active,
           topic=excluded.topic,version=excluded.version""",
        (actor.pair, actor.id, int(action != "end"), topic, version + 1),
    )
    bump_epoch(c, actor, invalidate_history=False)
    return mode_state(c, actor)


def attach_turn(c, actor, chat):
    # Older databases and clients have no per-module thread column.
    if chat["scope"] != "private" or ("module_id" in chat.keys() and chat["module_id"]):
        return
    c.execute(
        """INSERT OR IGNORE INTO profile_mode_turns(pair,owner,request_id,version)
           SELECT pair,owner,?,version FROM profile_modes WHERE pair=? AND owner=? AND active=1""",
        (chat["request_id"], actor.pair, actor.id),
    )


def mode_context(c, actor, chat, epoch):
    if chat["scope"] != "private" or chat["module_id"] is not None:
        return None
    if re.search(
        r"翻译|造句|语法|请(?:解释|写代码)|日语|学习|代码|技术问题|换个问题|不想聊这个|先聊别的",
        chat["input"],
    ):
        return None
    row = c.execute(
        """SELECT m.topic,m.version FROM profile_modes m JOIN profile_mode_turns t
           USING(pair,owner,version) WHERE m.pair=? AND m.owner=? AND m.active=1
           AND t.request_id=?""",
        (actor.pair, actor.id, chat["request_id"]),
    ).fetchone()
    if row is None:
        return None
    result = {"question": QUESTIONS[row["topic"]]}
    previous = c.execute(
        """SELECT h.output FROM chats h JOIN profile_mode_turns t USING(pair,owner,request_id)
           WHERE h.pair=? AND h.owner=? AND h.scope='private' AND h.done=1
           AND h.epoch=? AND t.version=? ORDER BY h.at DESC,h.rowid DESC LIMIT 1""",
        (actor.pair, actor.id, epoch, row["version"]),
    ).fetchone()
    if previous:
        result["previous_reply"] = json.loads(previous["output"])["reply"][-450:]
    return result


# Authorization commands are matched as entire utterances. A model never grants
# disclosure; a quoted phrase, question, hypothetical or negation cannot do so.
_SHARE = r"(?:(?:这(?:句|条|几条)|这句话|这条记忆|这些)(?:话|记忆|内容)?\s*)?(?:可以给(?:她|他|伴侣)看|可以公开给伴侣|确认发布给伴侣|发布给伴侣|分享给伴侣)"
_PRIVATE = r"(?:(?:这句|这条|这几条|这些)(?:话|记忆|内容)?\s*)?(?:先?(?:别|不要|不想)给(?:她|他|伴侣)看了?|先?(?:不要公开|别公开)了?|只(?:给自己|让DP|为我|为自己)记住|仅自己保存|仅自己可见|只让自己看|只让DP知道|只给DP看|只在私聊记住|仅自己保留|先不公开了?|撤回(?:公开|共享|发布)|改为私有|记住(?:这句|这条|这些)?|确认(?:保存|记住)|只给自己看)"
_DELETE = r"(?:(?:这句|这条|这几条)(?:话|记忆|内容)?\s*)?(?:不用记(?:了)?|别记(?:了)?|拒绝记住|删除(?:这句|这条|这几条|这条记忆)?|忘掉(?:这句|这条|这几条|这条记忆)?|跳过)"
_EDIT = r"(?:把这(?:句话|句|条(?:记忆)?)?)?(?:改成|改为|更正为|更新为|改写成)\s*(.+)"
_MODE_ACTIONS = {
    "我想让你了解我": "start",
    "让DP了解我": "start",
    "结束了解": "end",
    "退出了解模式": "end",
    "换个了解话题": "skip",
}


def _clean(text):
    return text.strip().rstrip("。！!.").strip()


def personal_statement(text):
    """Route first-person material to candidate review, never directly to publication."""
    s = _clean(text)
    if (
        not s
        or len(s) > 600
        or re.search(
            r"翻译|造句|日语|语法|写代码|如果|假设|比如|举例|[?？]|[「“].+[”」]|她说|他说|她喜欢|他喜欢",
            s,
        )
    ):
        return False
    if re.search(r"今天|此刻|这会儿|今天早上|今天晚上", s) and not re.search(
        r"平时|一向|通常|每次|每天", s
    ):
        return False
    return bool(
        re.search(
            r"我(?:平时|一向|通常|习惯|更?喜欢|不喜欢|更偏好|偏爱|不爱|希望对方|旅行时|出游时|觉得.{0,8}(?:最好|适合我))"
            r"|(?:出游|出行|旅行|旅游|度假).{0,10}(?:每天|一天|每次|最多|只想)"
            r"|(?:每天|一天).{0,4}(?:只想|最多).{0,14}(?:逛|地方|安排|主要)"
            r"|(?:平日|平时|生日).{0,12}(?:预算|开销)|记到(?:我的)?档案|请记住我的",
            s,
        )
    )


def prepare_reply(text, result):
    """Keep claims in ordinary tasks and passing moods out of the memory review list."""
    if personal_statement(text):
        # A model can identify an excerpt but cannot infer a trait for the nightly portrait.
        result["memories"] = [
            statement
            for statement in result["memories"]
            if _clean(statement) in text and personal_statement(statement)
        ]
        if (
            not result["memories"]
            and len(text) <= 300
            and not re.search(r"[，,；;：:\n]", text)
        ):
            result["memories"] = [_clean(text)]
    else:
        result["memories"] = []


def _command(text):
    s = _clean(text)
    for pattern, action in (
        (_SHARE, "shared"),
        (_PRIVATE, "private"),
        (_DELETE, "delete"),
    ):
        if re.fullmatch(pattern, s, flags=re.I):
            return action, None
    match = re.fullmatch(_EDIT, s)
    if match:
        words = match[1]
        parts = re.split(r"[，,；;。]\s*", words)
        action = "private"
        if len(parts) > 1 and re.fullmatch(_SHARE, parts[-1], flags=re.I):
            action = "shared"
            words = "，".join(parts[:-1])
        elif len(parts) > 1 and re.fullmatch(_PRIVATE, parts[-1], flags=re.I):
            words = "，".join(parts[:-1])
        # Do not interpret ambiguous disclosure qualifiers as part of a command.
        if any(
            suffix in words
            for suffix in (
                "给她看",
                "给他看",
                "给伴侣看",
                "发布给",
                "公开给",
                "？",
                "?",
            )
        ):
            return None, None
        return action, _clean(words)
    return None, None


def _focused(c, a):
    return c.execute(
        """SELECT m.*,f.version AS selected_version FROM profile_focus f JOIN memories m
           ON m.id=f.memory AND m.owner=f.owner AND m.pair=f.pair
           WHERE f.pair=? AND f.owner=? ORDER BY m.rowid""",
        (a.pair, a.id),
    ).fetchall()


def state(c, a):
    return {
        "daily_portrait": daily_portrait.for_owner(c, a),
        "profile_mode": mode_state(c, a),
        "profile_focus": [
            {"id": r["id"], "text": r["text"], "version": r["version"]}
            for r in _focused(c, a)
            if r["selected_version"] == r["version"]
        ],
    }


def _reply(c, a, row, text):
    from .business import read_epoch

    c.execute(
        """UPDATE chats SET output=?,done=1,epoch=? WHERE pair=? AND owner=? AND request_id=?""",
        (
            encode({"reply": text, "items": [], "memories": []}),
            read_epoch(c, a),
            a.pair,
            a.id,
            row["request_id"],
        ),
    )


def handle_private(c, a, row):
    from .business import Records
    from .intent import knowledge_request

    if row["scope"] != "private" or row["module_id"] is not None:
        return False
    text = _clean(row["input"])
    mode_action = _MODE_ACTIONS.get(text)
    if (
        not mode_action
        and text in ("退出", "跳过", "换个话题", "不想继续了解了")
        and mode_state(c, a)["active"]
    ):
        mode_action = "skip" if text in ("跳过", "换个话题") else "end"
    if mode_action:
        current = mode_state(c, a)
        if mode_action == "skip" and not current["active"]:
            return False
        next_mode = change_mode(c, a, mode_action, current["version"])
        _reply(
            c,
            a,
            row,
            next_mode["question"]["text"]
            if next_mode["active"]
            else "已结束了解模式，可以继续聊任何话题。",
        )
        return True
    action, revised = _command(text)
    if not action:
        return False
    if revised is not None and knowledge_request(text):
        return False
    items = _focused(c, a)
    if not items:
        if (revised is not None and action != "shared") or text == "跳过":
            return False
        _reply(c, a, row, "请在自己的档案中选择要处理的那条内容，再告诉我如何保存。")
        return True
    if c.execute(
        """SELECT 1 FROM chats WHERE pair=? AND owner=? AND scope='private' AND module_id IS NULL
        AND done=0 AND request_id<>? AND rowid>COALESCE(
            (SELECT through_turn FROM profile_selections WHERE pair=? AND owner=?),0
        ) LIMIT 1""",
        (a.pair, a.id, row["request_id"], a.pair, a.id),
    ).fetchone():
        c.execute("DELETE FROM profile_focus WHERE pair=? AND owner=?", (a.pair, a.id))
        _reply(c, a, row, "你还有未完成的对话，请在档案里选择你要处理的具体文字。")
        return True
    if text == "跳过" and any(i["scope"] != "candidate" for i in items):
        c.execute("DELETE FROM profile_focus WHERE pair=? AND owner=?", (a.pair, a.id))
        _reply(c, a, row, "已跳过，已保存的文字保持原样。")
        return True
    if any(i["version"] != i["selected_version"] for i in items):
        _reply(c, a, row, "这条资料刚刚被修改了，请在个人档案中核对最新文字再确认。")
        return True
    if len(items) > 1 and (revised is not None or not re.search(r"几条|这些", text)):
        _reply(
            c,
            a,
            row,
            "上次有多条候选。请从自己的档案选择其中一条，或明确确认这些条目。",
        )
        return True
    final = []
    for m in items:
        val = revised if revised is not None else m["text"]
        unchanged = action == m["scope"] and val == m["text"]
        if not unchanged:
            Records.change_memory(
                c, a, m["id"], m["version"], None if action == "delete" else val, action
            )
        if action != "delete":
            c.execute(
                "UPDATE profile_focus SET version=? WHERE pair=? AND owner=? AND memory=?",
                (m["version"] + int(not unchanged), a.pair, a.id, m["id"]),
            )
            final.append(val)
    reply = {
        "shared": "已向伴侣发布",
        "private": "已仅自己保存",
        "delete": "已从可用资料删除",
    }[action]
    _reply(c, a, row, reply + ("：“" + "”；“".join(final) + "”。" if final else "。"))
    return True


def after_reply(c, a, row, result):
    if row["scope"] != "private" or row["module_id"] is not None:
        return
    ids = (a.pair, a.id, row["request_id"])
    # An older in-flight generation must not steal the focus from a newer turn.
    newer = c.execute(
        """SELECT 1 FROM chats h WHERE h.pair=? AND h.owner=?
        AND h.scope='private' AND h.module_id IS NULL AND h.rowid>(
          SELECT rowid FROM chats WHERE pair=? AND owner=? AND request_id=?) LIMIT 1""",
        (a.pair, a.id, *ids),
    ).fetchone()
    selected = c.execute(
        """SELECT 1 FROM profile_selections f JOIN chats h USING(pair,owner)
        WHERE f.pair=? AND f.owner=? AND h.request_id=? AND h.rowid<=f.through_turn""",
        ids,
    ).fetchone()
    if newer or selected:
        return
    c.execute("DELETE FROM profile_focus WHERE pair=? AND owner=?", (a.pair, a.id))
    c.execute(
        """INSERT INTO profile_focus(pair,owner,memory,version)
        SELECT pair,owner,id,version FROM memories WHERE pair=? AND owner=? AND source=? AND scope='candidate'""",
        ids,
    )
    items = _focused(c, a)
    if items:
        preview = "；".join("「" + r["text"] + "」" for r in items)
        shown = {
            **result,
            "reply": result["reply"]
            + "\n\n待你确认，仅自己可见："
            + preview
            + "。可以改写、仅自己保存、发布给伴侣或拒绝记住。",
        }
        c.execute(
            "UPDATE chats SET output=? WHERE pair=? AND owner=? AND request_id=?",
            (encode(shown), *ids),
        )


class Revision(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    version: int = Field(ge=0)


def register(api, actor):
    from typing import Literal
    from .business import check_version, missing

    dependency = Depends(actor)

    @api.post("/v1/profile-mode/{action}")
    def mode(
        action: Literal["start", "skip", "end"],
        form: Revision,
        request: Request,
        a=dependency,
    ):
        service = request.app.state
        with service.records.release_lock, service.db.connection(True) as c:
            return change_mode(c, a, action, form.version)

    @api.post("/v1/profile-focus/{memory_id}")
    def focus(memory_id: str, form: Revision, request: Request, a=dependency):
        service = request.app.state
        with service.records.release_lock, service.db.connection(True) as c:
            row = c.execute(
                "SELECT version FROM memories WHERE id=? AND owner=? AND pair=?",
                (memory_id, a.id, a.pair),
            ).fetchone()
            if not row:
                missing()
            check_version(row["version"], form.version)
            c.execute(
                "DELETE FROM profile_focus WHERE pair=? AND owner=?", (a.pair, a.id)
            )
            c.execute(
                "INSERT INTO profile_focus VALUES(?,?,?,?)",
                (a.pair, a.id, memory_id, row["version"]),
            )
            c.execute(
                """INSERT INTO profile_selections VALUES(?,?,COALESCE((SELECT MAX(rowid) FROM chats
                WHERE pair=? AND owner=?),0)) ON CONFLICT(pair,owner) DO UPDATE SET through_turn=excluded.through_turn""",
                (a.pair, a.id, a.pair, a.id),
            )
            return {"ok": True}
