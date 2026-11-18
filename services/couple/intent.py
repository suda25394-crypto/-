"""Conservative routing: ordinary turns receive only conversation history."""

import re
import json

SAFETY = re.compile(r"报复|威胁|恐吓|殴打|打我|控制我|不敢回家|不安全|家暴|伤害我")
RELATION = re.compile(
    r"好消息|升职|获奖|拿到.{0,5}(offer|录取)|道歉|说重了|吵架|冷战|复盘|争执|分歧|约定|依恋|回避型|焦虑型|安全型|分手|离开关系|表达边界"
)
GENERAL = re.compile(
    r"语法|句型|翻译|日语|英语|そうだ|ようだ|编程|代码|数据库|技术问题|作文|造句|写一句|写一封|写.{0,4}鼓励|是什么时候上映"
    r"|\b(?:translat(?:e|ion)|programming|database|code sample|grammar)\b|翻訳|文法|プログラミング",
    re.I,
)
KNOWLEDGE = re.compile(
    r"什么是|是什么意思|有什么区别|的定义|的原理|(?:解释|科普|讲解)一下"
    r"|\b(?:what (?:is|are|does)|define|definition of|how does|difference between|explain)\b"
    r"|(?:とは何|とはどういう|の意味|の違い)|\b(?:qu[eé] es|c'est quoi|was ist)\b",
    re.I,
)
OUR_RECORD = re.compile(
    r"我们(?:的|俩|两人|已经|确认)|(?:我的|咱们的|双方的)(?:周末|预算|计划|安排|记录)|"
    r"\b(?:our|my saved|my confirmed)\b|私たちの",
    re.I,
)
PUBLIC_RECOMMENDATION = re.compile(
    r"推荐.{0,14}(?:一首|一张专辑|一本书|教材|入门书|一篇文章|播客|开源库|学习资源)"
    r"|\brecommend\b.{0,40}\b(?:song|album|textbook|article|podcast|library)\b",
    re.I,
)


def knowledge_request(text):
    if GENERAL.search(text):
        return True
    return bool(
        (KNOWLEDGE.search(text) or PUBLIC_RECOMMENDATION.search(text))
        and not OUR_RECORD.search(text)
    )


PRODUCT = re.compile(
    r"出游|旅行|行程|约会|日程|计划|心愿|回忆|委托|惊喜|周[末六日]|预算|花销|推荐|看什么|吃什么|挑.{0,6}电影|去哪|安排|依据|我不喜欢|我喜欢|我习惯|记住|改成|错峰|我更喜欢|birthday|plan|schedule",
    re.I,
)
EDIT = re.compile(r"(改[到成期为一下]?|调整|推迟|提前|修改|换到|移到)")
PLAN = re.compile(r"计划|约会|行程|日程")


def route(text, module_id=None):
    if SAFETY.search(text):
        return "safety"
    if (
        RELATION.search(text)
        and re.search(r"写.{0,6}道歉|道歉信", text)
        and not re.search(r"翻译|语法|造句|文法|translat", text, re.I)
    ):
        return "relationship"
    if knowledge_request(text):
        return "general"
    if RELATION.search(text):
        return "relationship"
    if PRODUCT.search(text):
        return "product"
    if module_id and re.search(
        r"这条|这件|这一|原来|当前|刚才|原定|具体|第二站|第一站|哪一站|那一站|终点|集合|改|几点|地址|改期",
        text,
    ):
        return "product"
    return "general"


def select_plan(c, a, text, request_id):
    if not (EDIT.search(text) and PLAN.search(text)):
        return None
    rows = c.execute(
        "SELECT id,title,body,module,version,owner FROM modules WHERE pair=? AND module IN ('date','calendar') ORDER BY rowid DESC",
        (a.pair,),
    ).fetchall()
    named = [r for r in rows if r["title"] and r["title"] in text]
    pool = (
        named
        or [r for r in rows if "周末" in r["title"] + r["body"] and "周末" in text]
        or rows
    )
    if len(pool) != 1:
        return None
    return dict(pool[0]) | {"scope": "shared"}


def conversational_context(c, a, scope, module_id, intent):
    # Only repeat replies derived from this same class of permission and conversation.
    rows = c.execute(
        """SELECT owner,input,output FROM chats WHERE pair=? AND scope=? AND module_id IS ?
        AND (scope='shared' OR owner=?) AND done=1 AND intent=? AND output IS NOT NULL
        AND epoch>=COALESCE((SELECT epoch FROM dp_history_floor WHERE pair=chats.pair),0)
        ORDER BY at DESC,rowid DESC LIMIT 4""",
        (a.pair, scope, module_id, a.id, intent),
    ).fetchall()
    history = []
    for r in reversed(rows):
        history.extend(
            (
                {"role": "user", "owner": r["owner"], "text": r["input"][:1200]},
                {"role": "assistant", "text": json.loads(r["output"])["reply"][:1400]},
            )
        )
    context = {
        k: []
        for k in (
            "profiles",
            "memories",
            "modules",
            "history",
            "module_target",
            "feedback",
            "activity_decisions",
            "activity_experiences",
            "mandates",
        )
    }
    context.update(conversation=history, speaker=[{"id": a.id}], intent=[intent])
    if intent == "relationship" and scope == "shared":
        from .relationship import context as active

        context["reflections"] = active(c, a)
    return context
