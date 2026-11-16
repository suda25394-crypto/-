"""Browser smoke test for the local V1; no account or network service required."""

import argparse
import re
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

MODULES = ["约会", "惊喜", "共同记忆", "心愿", "小宇宙", "美食", "共同日程", "关系沟通", "情侣相册", "互动游戏", "礼物灵感", "旅行"]
PREFERENCE = "我不喜欢人多"
PLAN = "周末想和女朋友出去玩，预算 200 元。"
NEW_TITLE = "沿河散步与热茶"


def assert_layout(page, label, one_screen=False):
    sizes = page.evaluate("""() => ({
        horizontal: document.documentElement.scrollWidth - innerWidth,
        vertical: document.documentElement.scrollHeight - innerHeight
    })""")
    assert sizes["horizontal"] <= 1, (label, sizes)
    if one_screen:
        assert sizes["vertical"] <= 1, (label, sizes)


def navigate(page, path):
    page.evaluate("(path) => { location.hash = path }", path)
    page.wait_for_function("(path) => location.hash === path", arg=path)


def send(page, text):
    page.get_by_role("textbox", name="输入消息").fill(text)
    page.get_by_role("button", name="发送消息").tap()


def switch_identity(page, letter):
    page.get_by_role("button", name=re.compile("切换演示账号，当前")).tap()
    page.get_by_role("dialog").get_by_role("button", name=re.compile("演示 " + letter)).tap()


def run_view(browser, origin, width, height, evidence):
    context = browser.new_context(
        viewport={"width": width, "height": height}, is_mobile=True, has_touch=True,
        locale="zh-CN", reduced_motion="reduce" if width == 360 else "no-preference",
    )
    page = context.new_page()
    failures = []
    requests = []
    page.on("pageerror", lambda error: failures.append(str(error)))
    page.on("console", lambda msg: failures.append(msg.text) if msg.type == "error" else None)
    page.on("request", lambda request: requests.append(request.url))

    def screenshot(name):
        if evidence and (width == 390 or name == "home"):
            expect(page.locator("#status")).to_be_hidden()
            page.wait_for_timeout(450)  # Wait for the platform's touch highlight to fade in evidence images.
            page.screenshot(path=str(evidence / f"{name}-{width}.png"))

    try:
        page.goto(origin)
        expect(page.get_by_role("heading", name="你们的 AI 中枢")).to_be_visible()
        expect(page.get_by_role("link", name="和 AI 聊聊")).to_be_visible()
        expect(page.locator(".orbit-node")).to_have_count(4)
        assert_layout(page, "首页", one_screen=True)
        screenshot("home")

        page.get_by_role("link", name="功能", exact=True).tap()
        expect(page.locator(".directory-card")).to_have_count(12)
        assert_layout(page, "功能目录")
        screenshot("modules")
        for index, label in enumerate(MODULES):
            page.locator(".directory-card").nth(index).tap()
            heading = "我们的小宇宙" if label == "小宇宙" else label
            expect(page.get_by_role("heading", name=heading, exact=True)).to_be_visible()
            page.locator(".detail-box summary").tap()
            expect(page.locator(".detail-text")).to_be_visible()
            expect(page.get_by_role("link", name="编辑内容")).to_be_visible()
            expect(page.get_by_role("link", name="让 AI 调整")).to_be_visible()
            assert_layout(page, label)
            if label == "小宇宙":
                assert page.url.endswith("#/universe")
                screenshot("universe")
            page.get_by_role("link", name="编辑内容").tap()
            expect(page.get_by_role("heading", name="编辑" + label, exact=True)).to_be_visible()
            expect(page.get_by_label("标题", exact=True)).to_be_editable()
            page.get_by_role("link", name="返回").tap()
            page.get_by_role("link", name="返回").tap()

        page.get_by_role("link", name="中枢", exact=True).tap()
        page.get_by_role("link", name="和 AI 聊聊").tap()
        send(page, PLAN)
        expect(page.locator(".suggestion")).to_have_count(4)
        screenshot("director")
        navigate(page, "#/")
        expect(page.locator(".orbit-node").filter(has_text="共同日程")).to_be_visible()
        expect(page.locator(".orbit-node").filter(has_text="旅行")).to_be_visible()
        page.get_by_role("link", name="和 AI 聊聊").tap()
        suggestion = page.locator(".suggestion").filter(has_text="约会")
        restricted_draft = suggestion.get_attribute("href")
        suggestion.tap()
        expect(page.get_by_text("AI 草稿 · 待确认")).to_be_visible()
        page.locator("summary").tap()
        expect(page.get_by_text("预算上限：200 元", exact=False)).to_be_visible()
        page.get_by_role("link", name="编辑内容").tap()
        page.get_by_label("标题", exact=True).fill(NEW_TITLE)
        page.get_by_label("摘要", exact=True).fill("沿河走一走，再去喝杯热茶。")
        page.get_by_role("button", name="查看 AI 确认").tap()
        modal = page.get_by_role("dialog")
        expect(modal.get_by_text("你调整了标题、摘要。", exact=False)).to_be_visible()
        expect(modal.get_by_role("button", name="继续编辑")).to_be_focused()
        screenshot("confirmation")
        page.keyboard.press("Escape")
        expect(modal).not_to_be_visible()
        expect(page.get_by_label("标题", exact=True)).to_have_value(NEW_TITLE)
        page.get_by_role("link", name="返回").tap()
        expect(page.get_by_role("heading", name=NEW_TITLE, exact=True)).not_to_be_visible()
        page.get_by_role("link", name="编辑内容").tap()
        page.get_by_label("标题", exact=True).fill(NEW_TITLE)
        page.get_by_role("button", name="查看 AI 确认").tap()
        modal.get_by_role("radio", name="共同内容，两位演示用户可见").check()
        modal.get_by_role("checkbox", name="将这次修改加入我的演示记忆").check()
        modal.get_by_role("button", name="确认保存").tap()
        expect(page.get_by_role("heading", name=NEW_TITLE, exact=True)).to_be_visible()
        page.reload()
        expect(page.get_by_role("heading", name=NEW_TITLE, exact=True)).to_be_visible()

        page.get_by_role("link", name="编辑内容").tap()
        page.get_by_label("标题", exact=True).fill("我自己的约会笔记")
        page.get_by_role("button", name="查看 AI 确认").tap()
        modal.get_by_role("radio", name="我的演示内容").check()
        modal.get_by_role("button", name="确认保存").tap()
        expect(page.get_by_role("heading", name="我自己的约会笔记")).to_be_visible()
        page.get_by_role("link", name="查看共同版本").tap()
        expect(page.get_by_role("heading", name=NEW_TITLE, exact=True)).to_be_visible()
        page.get_by_role("link", name="查看我的版本").tap()
        expect(page.get_by_role("heading", name="我自己的约会笔记")).to_be_visible()

        navigate(page, "#/profiles/a")
        expect(page.get_by_role("heading", name="我们的小档案")).to_be_visible()
        expect(page.get_by_text("尚未测量", exact=True)).to_be_visible()
        screenshot("profiles")
        page.get_by_text("我的演示记忆 · 1 条").tap()
        expect(page.get_by_text("约会 · " + NEW_TITLE, exact=True)).to_be_visible()
        page.get_by_role("link", name="编辑我的档案").tap()
        page.get_by_label("生活偏好", exact=True).fill("热茶与散步")
        page.get_by_role("button", name="保存档案").tap()
        expect(page.get_by_role("heading", name="我们的小档案")).to_be_visible()
        navigate(page, "#/chat/personal")
        expect(page.get_by_role("heading", name="小智", exact=True)).to_be_visible()
        send(page, PREFERENCE)
        expect(page.get_by_role("button", name="加入我的档案")).to_be_visible()
        switch_identity(page, "B")
        expect(page.locator(".message", has_text=PREFERENCE)).to_have_count(0)
        navigate(page, restricted_draft)
        expect(page.get_by_role("heading", name="这份草稿暂不可用")).to_be_visible()
        navigate(page, "#/profiles/b")
        expect(page.get_by_text("我的演示记忆 · 0 条")).to_be_visible()
        navigate(page, "#/profiles/a/edit")
        expect(page.get_by_role("heading", name="我们的小档案")).to_be_visible()
        expect(page.get_by_role("link", name="编辑我的档案")).to_have_count(0)
        page.get_by_text("生活与相处偏好", exact=True).tap()
        expect(page.get_by_text("热茶与散步", exact=True)).to_be_visible()
        expect(page.get_by_text(PREFERENCE, exact=True)).to_have_count(0)
        navigate(page, "#/modules/date")
        expect(page.get_by_role("heading", name=NEW_TITLE, exact=True)).to_be_visible()

        navigate(page, "#/chat/personal")
        switch_identity(page, "A")
        page.get_by_role("button", name="加入我的档案").tap()
        expect(page.get_by_text("已确认加入我的档案")).to_be_visible()
        send(page, "周末安排约会")
        expect(page.locator(".suggestion", has_text="去一个清静的地方约会")).to_be_visible()
        send(page, "我喜欢代码示例 <img src=x onerror=alert(1)>")
        expect(page.get_by_text("<img src=x onerror=alert(1)>", exact=False).first).to_be_visible()
        assert page.locator(".chat-feed img").count() == 0

        page.get_by_role("link", name="共同空间").tap()
        send(page, "先在共同空间打声招呼")
        expect(page.locator(".message.assistant")).to_have_count(0)
        send(page, "@AI 周末去哪里玩")
        expect(page.locator(".suggestion")).to_have_count(4)
        switch_identity(page, "B")
        expect(page.get_by_text("先在共同空间打声招呼", exact=True)).to_be_visible()
        expect(page.locator(".suggestion")).to_have_count(4)
        expect(page.get_by_text(PREFERENCE, exact=True)).to_have_count(0)
        assert_layout(page, "共同空间")
        navigate(page, "#/profiles/a")
        page.get_by_text("生活与相处偏好", exact=True).tap()
        expect(page.get_by_text(PREFERENCE, exact=True)).to_be_visible()
        assert not failures, failures
        assert all(url.startswith(origin + "/") for url in requests), requests
        print(f"PASS {width}x{height} · 12 module routes, universe, director, cancel/confirm, profiles, shared chat, reload, no overflow")
    finally:
        context.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--origin", default="http://127.0.0.1:4173")
    parser.add_argument("--chrome", help="path to an existing Chrome executable")
    parser.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    if args.evidence:
        args.evidence.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(executable_path=args.chrome, headless=True)
        try:
            for width, height in ((360, 800), (390, 844)):
                run_view(browser, args.origin.rstrip("/"), width, height, args.evidence)
        finally:
            browser.close()


if __name__ == "__main__":
    main()
