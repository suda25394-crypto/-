"""Test a disposable Open WebUI instance using separate authenticated sessions."""

import argparse
import json
import secrets
import time
from contextlib import ExitStack
from urllib.parse import urlsplit

import httpx

AUTH = "/api/v1/auths"
CHANNELS = "/api/v1/channels"
CHATS = "/api/v1/chats"
MENTION = "<@M:deepseek-flash|AI>"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def ok(response):
    return response.raise_for_status().json()


def login(client, user):
    signed_in = ok(client.post(f"{AUTH}/signin", json={key: user[key] for key in ("email", "password")}))
    client.headers["Authorization"] = f"Bearer {signed_in['token']}"
    return signed_in["id"]


def verify_browsers(origin, browser_executable, identities, channel_id, fixture_reply):
    from playwright.sync_api import expect, sync_playwright

    with sync_playwright() as browser_tools:
        browser = browser_tools.chromium.launch(executable_path=browser_executable, headless=True)
        pages = []
        try:
            for user in identities:
                page = browser.new_context(
                    viewport={"width": 390, "height": 844}, is_mobile=True, has_touch=True, locale="en-US"
                ).new_page()
                page.goto(f"{origin}/auth", wait_until="domcontentloaded")
                page.locator('input[inputmode="email"]').fill(user["email"])
                page.locator('input[type="password"]').fill(user["password"])
                page.get_by_role("button", name="Sign in", exact=True).click()
                page.wait_for_url(lambda url: "/auth" not in url)
                page.goto(f"{origin}/channels/{channel_id}", wait_until="domcontentloaded")
                page.get_by_text("shared-message-a", exact=True).wait_for()
                page.get_by_text("shared-message-b", exact=True).wait_for()
                pages.append(page)
            print("PASS: two isolated mobile browser sessions signed in and rendered the same channel")

            if fixture_reply is None:
                return None

            sender, partner = pages
            composer = sender.locator("#chat-input")
            composer.tap()
            sender.keyboard.type("@AI")
            sender.locator(".mention-list button").filter(has_text="AI").tap()
            prompt = "请确认两人都能看到这条群聊消息。"
            sender.keyboard.insert_text(prompt)
            post_url = f"{origin}{CHANNELS}/{channel_id}/messages/post"
            with sender.expect_response(
                lambda response: response.url == post_url and response.request.method == "POST"
            ) as result:
                sender.get_by_role("button", name="Send message", exact=True).tap()
            response = result.value
            require(response.ok, f"Mobile composer send failed with status {response.status}")
            posted = response.json()
            require(MENTION in posted["content"], "The mobile composer did not serialize the AI mention")

            for page in (partner, sender):
                expect(page.get_by_text(prompt)).to_be_visible(timeout=15_000)
                page.get_by_role("button", name="1 Replies").tap(timeout=20_000)
                expect(page.get_by_text(fixture_reply, exact=True)).to_be_visible(timeout=15_000)
            print("PASS: tapped @AI and sent in one mobile session, then both opened the reply without refreshing")
            return posted["id"]
        finally:
            browser.close()


def verify(origin, fixture_reply=None, browser_executable=None):
    with ExitStack() as stack:
        admin, a, b, outsider = [
            stack.enter_context(httpx.Client(base_url=origin, timeout=20, trust_env=False))
            for _ in range(4)
        ]
        require(ok(admin.get("/api/config")).get("onboarding"), "Use a fresh test instance with an empty database")

        def identity(name):
            return {"name": name, "email": f"{name.lower()}@example.com", "password": secrets.token_urlsafe(24)}

        owner = identity("SmokeAdmin")
        require(ok(admin.post(f"{AUTH}/signup", json=owner))["role"] == "admin", "Bootstrap must create an admin")
        login(admin, owner)
        identities = [identity(name) for name in ("SmokeA", "SmokeB", "SmokeOutsider")]
        for user in identities:
            ok(admin.post(f"{AUTH}/add", json={**user, "role": "user"}))
        ids = [login(client, user) for client, user in zip((a, b, outsider), identities, strict=True)]
        require(len(set(ids)) == 3, "Account identities must be distinct")
        require(outsider.post(f"{AUTH}/signup", json=identity("SmokeDenied")).status_code in (401, 403),
                "Signup should be disabled after bootstrap")
        ok(admin.post("/api/v1/models/model/access/update", json={
            "id": "deepseek-flash",
            "name": "AI",
            "access_grants": [
                {"principal_type": "user", "principal_id": user_id, "permission": "read"}
                for user_id in ids[:2]
            ],
        }))
        require(not any(model["id"] == "deepseek-flash" for model in ok(outsider.get("/api/models"))["data"]),
                "Nonmember can access ungranted DeepSeek model")
        for client in (a, b):
            found_model = ok(client.get("/api/models"))["data"]
            require(any(model["id"] == "deepseek-flash" and model["name"] == "AI" for model in found_model),
                    "Both paired users must see the same DeepSeek model")
        print("PASS: separate accounts, closed signup, both accounts see AI")

        for owner_client, partner_client in ((a, b), (b, a)):
            marker = f"private-{secrets.token_hex(6)}"
            chat = ok(owner_client.post(f"{CHATS}/new", json={"chat": {"title": marker, "messages": []}}))
            path = f"{CHATS}/{chat['id']}"
            require(marker in json.dumps(ok(owner_client.get(path))), "Chat owner cannot retrieve private chat")
            for other in (partner_client, outsider, admin):
                require(other.get(path).status_code in (401, 403, 404), "Foreign private chat was readable by ID")
                require(marker not in json.dumps(ok(other.get(f"{CHATS}/"))), "Foreign chat was listed")
        print("PASS: private chats isolated in both directions and inaccessible via admin chat API")

        channel = ok(a.post(f"{CHANNELS}/create", json={
            "type": "group", "name": "Smoke Shared", "is_private": True, "user_ids": [ids[1]],
        }))
        path = f"{CHANNELS}/{channel['id']}"
        members = ok(a.get(f"{path}/members"))["users"]
        require({member["id"] for member in members} == set(ids[:2]), "Channel member set differs from the couple")
        for sender, receiver, text in ((a, b, "shared-message-a"), (b, a, "shared-message-b")):
            ok(sender.post(f"{path}/messages/post", json={"content": text}))
            require(any(message["content"] == text for message in ok(receiver.get(f"{path}/messages"))),
                    "Partner's message did not appear")
        require(channel["id"] not in json.dumps(ok(outsider.get(f"{CHANNELS}/"))), "Channel listed for nonmember")
        for route in (path, f"{path}/messages"):
            require(outsider.get(route).status_code in (401, 403, 404), "Channel readable by nonmember")
        require(outsider.post(f"{path}/messages/post", json={"content": "denied"}).status_code in (401, 403, 404),
                "Nonmember could post to channel")
        print("PASS: Group Channel shared by A/B; third account denied list/read/post")

        post_id = None
        if browser_executable:
            post_id = verify_browsers(origin, browser_executable, identities[:2], channel["id"], fixture_reply)

        if fixture_reply:
            if post_id is None:
                post = ok(a.post(f"{path}/messages/post", json={"content": f"{MENTION} 验证模型链路"}))
                post_id = post["id"]
            thread = f"{path}/messages/{post_id}/thread"
            deadline = time.monotonic() + 20
            for client in (b, a):
                while time.monotonic() < deadline:
                    replies = ok(client.get(thread))
                    if any(message["content"] == fixture_reply for message in replies):
                        break
                    time.sleep(0.25)
                else:
                    raise AssertionError("AI fixture reply was not visible to both members")
            require(outsider.get(thread).status_code in (401, 403, 404), "Nonmember could read AI reply")
            print("PASS: both users saw a real Open WebUI @AI thread reply from the offline test fixture")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fresh-local-test", required=True, help="loopback URL of a disposable instance")
    parser.add_argument("--fixture-reply", help="match a known response from an offline fixture")
    parser.add_argument("--browser-executable", help="optional installed Chromium executable (requires Playwright)")
    args = parser.parse_args()
    origin = urlsplit(args.fresh_local_test)
    if (origin.scheme != "http" or origin.hostname != "127.0.0.1" or not origin.port
            or origin.username or origin.password or origin.path not in ("", "/") or origin.query or origin.fragment):
        parser.error("Use http://127.0.0.1:PORT for an isolated instance.")
    verify(f"http://127.0.0.1:{origin.port}", args.fixture_reply, args.browser_executable)


if __name__ == "__main__":
    main()
