"""Smoke test V2 in 360×800 and 390×844 touch viewports."""

import argparse
import io
import re
from pathlib import Path

from PIL import Image
from playwright.sync_api import expect, sync_playwright

SAMPLES = {
    "a": "立体生命中枢", "b": "情侣生活杂志", "c": "2.5D 浪漫空间",
}
PAGES = {"home": "周末，想怎么过？", "modules": "十二项功能", "universe": "湖畔观测站"}
PAIRS = [
    ("--ink", "--bg"), ("--muted", "--bg"), ("--muted", "--surface"),
    ("--main", "--bg"), ("#ffffff", "--main"), ("--ink", "--aux"),
    ("--ink", "--creative"), ("--ink", "--warm"),
    ("--ink", "#e5e8fa"), ("--ink", "#f5e8d8"), ("--ink", "#e6dcf5"),
]


def luminance(color):
    values = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in values]
    return sum(v * w for v, w in zip(linear, (0.2126, 0.7152, 0.0722), strict=True))


def assert_contrast(page):
    values = page.evaluate("""pairs => pairs.map(pair => pair.map(token =>
        token.startsWith('--') ? getComputedStyle(document.body).getPropertyValue(token).trim() : token
    ))""", PAIRS)
    ratios = []
    for colors in values:
        darker, lighter = sorted(luminance(color) for color in colors)
        ratio = (lighter + 0.05) / (darker + 0.05)
        assert ratio >= 4.5, (colors, ratio)
        ratios.append(ratio)
    return ratios


def assert_layout(page, one_screen=False):
    overflow = page.evaluate("""() => [
        document.documentElement.scrollWidth - innerWidth, document.documentElement.scrollHeight - innerHeight
    ]""")
    assert overflow[0] <= 1, overflow
    if one_screen:
        assert overflow[1] <= 1, overflow


def ready(page, view):
    expect(page.get_by_role("heading", name=re.compile("周末，\\s*想怎么过？") if view == "home" else PAGES[view])).to_be_visible()
    page.locator("img.art").evaluate_all("images => Promise.all(images.map(image => image.decode()))")
    assert_layout(page, view == "home")


def capture(page, output, direction, view):
    if not output:
        return
    with Image.open(io.BytesIO(page.screenshot())) as screenshot:
        screenshot.save(output / f"{direction}-{view}.webp", "WEBP", quality=88, method=6)


def preview(context, origin, direction, output):
    page = context.new_page()
    issues = []
    page.on("pageerror", lambda issue: issues.append(str(issue)))
    page.on("console", lambda message: issues.append(message.text) if message.type == "error" else None)
    page.on("response", lambda response: issues.append(str(response.status) + " " + response.url)
            if response.status >= 400 else None)
    page.goto(f"{origin}/sample.html?direction={direction}")
    ready(page, "home")
    ratios = assert_contrast(page)
    capture(page, output, direction, "home")
    expect(page.locator(".home button.ask")).to_have_count(1)
    page.get_by_role("button", name="查看双人档案").tap()
    expect(page.get_by_role("dialog").get_by_text("阿澄", exact=True)).to_be_visible()
    page.keyboard.press("Escape")
    page.get_by_role("button", name="告诉 AI 你的想法").tap()
    page.get_by_role("textbox").fill("给她一个生日惊喜")
    page.get_by_role("button", name="看看 AI 怎么安排").tap()
    expect(page.get_by_role("heading", name="AI 整理结果")).to_be_visible()
    expect(page.get_by_role("dialog").get_by_role("button", name="礼物灵感")).to_be_visible()
    page.get_by_role("button", name="返回查看").tap()
    expect(page.locator(".recommendation").get_by_role("button", name="礼物灵感")).to_be_visible()

    page.locator("#nav").get_by_role("link", name="功能", exact=True).tap()
    ready(page, "modules")
    capture(page, output, direction, "modules")
    modules = page.locator(".directory [data-module]")
    expect(modules).to_have_count(12)
    assert len(set(modules.evaluate_all("nodes => nodes.map(node => node.dataset.module)"))) == 12
    for id in modules.evaluate_all("nodes => nodes.map(node => node.dataset.module)"):
        if id == "universe":
            continue
        page.locator(f'[data-module="{id}"]').tap()
        expect(page.get_by_role("dialog")).to_be_visible()
        page.get_by_text("查看详情", exact=True).tap()
        expect(page.locator("dialog .preline")).to_be_visible()
        page.get_by_role("button", name="关闭", exact=True).tap()
    page.locator('[data-module="universe"]').tap()
    ready(page, "universe")
    capture(page, output, direction, "universe")
    expect(page.get_by_role("heading", name="湖边的第一盏灯")).to_be_visible()
    expect(page.get_by_text("阿澄", exact=True)).to_be_visible()
    if direction == "b":
        page.get_by_role("button", name="看场景").tap()
    page.get_by_role("button", name="信笺角").tap()
    expect(page.locator(".place-note")).to_contain_text("小屿写下")
    page.get_by_role("button", name="和 AI 改写这个世界").tap()
    page.get_by_role("button", name="使用示例").tap()
    page.get_by_role("button", name="看看 AI 怎么安排").tap()
    expect(page.get_by_role("dialog").get_by_text("窗灯", exact=False)).to_be_visible()
    page.get_by_role("button", name="返回查看").tap()
    expect(page.get_by_text("AI 草案", exact=False)).to_be_visible()
    assert not issues, issues
    tasks = page.evaluate("window.visualLongTasks ?? []")
    print(f"{direction.upper()} {page.viewport_size}: 3 pages and 12 entries, contrast {min(ratios):.2f}:1+, "
          f"long tasks on local sample {tasks}")
    page.close()


def review(context, origin, width):
    page = context.new_page()
    page.goto(origin + "/")
    expect(page.get_by_role("heading", name="手机视觉抽卡")).to_be_visible()
    assert_layout(page)
    page.locator("#size").select_option(str(width))
    page.locator('[data-direction="b"]').tap()
    page.locator('[data-page="universe"]').tap()
    phone = page.frame_locator("#phone")
    expect(phone.get_by_text("湖畔观测站", exact=True)).to_be_visible()
    assert phone.locator("html").evaluate("() => innerWidth") == width
    page.locator("#favorite").tap()
    page.locator("#rating").select_option("5")
    page.reload()
    page.locator('[data-direction="b"]').tap()
    expect(page.locator("#favorite")).to_have_attribute("aria-pressed", "true")
    expect(page.locator("#rating")).to_have_value("5")
    page.locator("#size").select_option(str(width))
    page.locator('[data-page="modules"]').tap()
    page.locator("#compare").tap()
    expect(page.locator("#comparisons figure img")).to_have_count(3)
    page.locator("#comparisons img").evaluate_all("images => Promise.all(images.map(image => image.decode()))")
    assert_layout(page)
    page.locator('[data-open="c"]').tap()
    expect(phone.get_by_text("十二项功能", exact=True)).to_be_visible()
    page.evaluate("window.scrollTo(0, document.documentElement.scrollHeight)")
    phone.locator("#nav").get_by_role("link", name="小宇宙").tap()
    expect(page.locator('[data-page="universe"]')).to_have_attribute("aria-pressed", "true")
    page.locator("#direct").get_attribute("href")
    print(f"Review {width}: A/B/C switch, exact phone width, ratings/favorite after reload, comparison and iframe navigation")
    page.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--origin", default="http://127.0.0.1:4174/visual-v2/")
    parser.add_argument("--chrome", help="path to an existing Chrome executable")
    parser.add_argument("--capture", type=Path, help="write viewport evidence")
    args = parser.parse_args()
    with sync_playwright() as manager:
        browser = manager.chromium.launch(executable_path=args.chrome, headless=True)
        try:
            for width, height in ((360, 800), (390, 844)):
                context = browser.new_context(viewport={"width": width, "height": height}, is_mobile=True,
                                              has_touch=True, locale="zh-CN",
                                              reduced_motion="reduce" if width == 360 else "no-preference")
                context.add_init_script("""window.visualLongTasks = [];
                  if (PerformanceObserver.supportedEntryTypes.includes('longtask')) {
                    new PerformanceObserver(list => list.getEntries().forEach(item =>
                      window.visualLongTasks.push(Math.round(item.duration)))).observe({type:'longtask',buffered:true});
                  }""")
                evidence = args.capture / f"{width}x{height}" if args.capture else None
                if evidence:
                    evidence.mkdir(parents=True, exist_ok=True)
                for direction in SAMPLES:
                    preview(context, args.origin.rstrip("/"), direction, evidence)
                review(context, args.origin.rstrip("/"), width)
                context.close()
        finally:
            browser.close()


if __name__ == "__main__":
    main()
