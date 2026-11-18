"""Optional local E2E. Supply Python executables only; hosts and disposable credentials are generated here."""

import argparse
import os
import secrets
import socket
import sqlite3
import subprocess
import tempfile
import time
from contextlib import ExitStack, closing
from pathlib import Path

import httpx
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from services.couple.api import create_app
from services.couple.database import Settings
from services.couple.upstream import Upstream, UpstreamConfig

GATEWAY_REV = "28a1e2653393e35567911677d9646924342d8d77"


def port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def start(stack, exe, module, at, env, cwd):
    output = stack.enter_context((cwd / (module.split(":")[0] + ".log")).open("wb"))
    # Only injected fixture services can provide a model to this Open WebUI instance.
    p = subprocess.Popen(
        [
            str(exe),
            "-m",
            "uvicorn",
            module,
            "--host",
            "127.0.0.1",
            "--port",
            str(at),
            *(["--factory"] if module.endswith(":factory") else []),
        ],
        cwd=cwd,
        env={
            **{
                k: v
                for k, v in os.environ.items()
                if k.upper()
                in {
                    "PATH",
                    "SYSTEMROOT",
                    "WINDIR",
                    "COMSPEC",
                    "PATHEXT",
                    "TEMP",
                    "TMP",
                    "LOCALAPPDATA",
                    "APPDATA",
                    "PROGRAMDATA",
                    "USERPROFILE",
                    "HOME",
                    "LANG",
                }
            },
            **(
                {"PYTHONPATH": os.environ["COUPLE_TEST_PYTHONPATH"]}
                if os.getenv("COUPLE_TEST_PYTHONPATH")
                else {}
            ),
            **env,
            "PYTHONUTF8": "1",
        },
        stdout=output,
        stderr=subprocess.STDOUT,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )

    def stop():
        p.terminate()
        try:
            p.wait(timeout=15)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()

    stack.callback(stop)
    url = f"http://127.0.0.1:{at}"
    with httpx.Client(trust_env=False, timeout=0.8) as c:
        deadline = time.monotonic() + 130
        while time.monotonic() < deadline and p.poll() is None:
            try:
                if c.get(url + "/health").is_success:
                    return url
            except httpx.HTTPError:
                pass
            time.sleep(0.3)
    log = (
        (cwd / (module.split(":")[0] + ".log"))
        .read_text(encoding="utf-8", errors="replace")
        .splitlines()
    )
    for line in log:
        if line.startswith(
            (
                "ImportError:",
                "ModuleNotFoundError:",
                "FileNotFoundError:",
                "RuntimeError:",
                "ValueError:",
                "PermissionError:",
                "AttributeError:",
                "Fatal Python error:",
                "Error:",
            )
        ):
            print(line[:300], flush=True)
    if not any(line.startswith("Traceback") for line in log):
        print(
            "Startup diagnostic",
            [
                line[:130]
                for line in log[-3:]
                if "key" not in line.lower() and "token" not in line.lower()
            ],
            flush=True,
        )
    else:
        print("Startup exception type:", log[-1].partition(":")[0][:100], flush=True)
    print("Local service exit", p.poll(), flush=True)
    raise RuntimeError(f"Local test service did not start: {module}")


def ok(r):
    if not r.is_success:
        raise AssertionError(
            f"{r.request.method} {r.request.url.path} returned {r.status_code}"
        )
    return r.json()


def run(web_py, gateway_py):
    import yaml

    project = Path(__file__).resolve().parents[3]

    def from_git(path):
        return subprocess.check_output(
            ["git", "show", f"{GATEWAY_REV}:demo/{path}"], cwd=project
        )

    with (
        tempfile.TemporaryDirectory(prefix="couple-contract-") as temp,
        ExitStack() as stack,
    ):
        cwd = Path(temp)
        (cwd / "gateway.py").write_bytes(from_git("gateway.py"))
        (cwd / "fixture_gateway.py").write_bytes(
            (Path(__file__).parent / "fixture_gateway.py").read_bytes()
        )
        secret = secrets.token_hex(32)
        gw = start(
            stack,
            gateway_py,
            "fixture_gateway:factory",
            port(),
            {
                "DEEPSEEK_ENABLED": "true",
                "DEEPSEEK_API_KEY": "local-fixture-only",
                "DEMO_GATEWAY_TOKEN": secret,
                "DEMO_BUDGET_DB": str(cwd / "budget.db"),
                "DEMO_DAILY_REQUESTS": "4",
                "DEMO_MAX_OUTPUT_TOKENS": "1024",
            },
            cwd,
        )
        config = yaml.safe_load(from_git("compose.yaml"))["services"]["webui"][
            "environment"
        ]
        env = {k: v for k, v in config.items() if "${" not in str(v)}
        web_port = port()
        origin = f"http://127.0.0.1:{web_port}"
        env.update(
            OPENAI_API_BASE_URLS=gw + "/v1",
            OPENAI_API_KEYS=secret,
            OPENAI_API_KEY=secret,
            WEBUI_SECRET_KEY=secrets.token_hex(32),
            WEBUI_AUTH_COOKIE_SECURE="false",
            WEBUI_URL=origin,
            CORS_ALLOW_ORIGIN=origin,
            USE_SLIM_DOCKER="true",
            STATIC_DIR=str(cwd / "static"),
            DATA_DIR=str(cwd / "webui"),
            ENV="prod",
            OFFLINE_MODE="true",
        )
        (cwd / "webui").mkdir()
        frontend = subprocess.check_output(
            [
                str(web_py),
                "-c",
                "import importlib.util,pathlib,sys; sys.stdout.buffer.write(str(pathlib.Path(importlib.util.find_spec('open_webui').origin).parent / 'frontend').encode('utf-8'))",
            ]
        ).decode("utf-8")
        env["FRONTEND_BUILD_DIR"] = frontend
        web = start(stack, web_py, "open_webui.main:app", web_port, env, cwd)
        admin = stack.enter_context(
            httpx.Client(base_url=web, trust_env=False, timeout=15)
        )

        def user(name):
            return {
                "name": name,
                "email": name.lower() + "@example.com",
                "password": secrets.token_urlsafe(24),
            }

        master = user("FixtureAdmin")
        created = ok(admin.post("/api/v1/auths/signup", json=master))
        assert created["role"] == "admin"
        admin.headers["Authorization"] = "Bearer " + created["token"]
        users = [user("FixtureA"), user("FixtureB"), user("FixtureOutside")]
        ids = [
            ok(admin.post("/api/v1/auths/add", json={**u, "role": "user"}))["id"]
            for u in users
        ]
        a_native = stack.enter_context(
            httpx.Client(base_url=web, trust_env=False, timeout=15)
        )
        a_native.headers["Authorization"] = (
            "Bearer "
            + ok(a_native.post("/api/v1/auths/signin", json=users[0]))["token"]
        )
        channel = ok(
            a_native.post(
                "/api/v1/channels/create",
                json={
                    "name": "Fixture couple",
                    "type": "group",
                    "is_private": True,
                    "user_ids": [ids[1]],
                },
            )
        )["id"]
        ok(
            admin.post(
                "/api/v1/models/model/access/update",
                json={
                    "id": "deepseek-flash",
                    "name": "AI",
                    "access_grants": [
                        {
                            "principal_type": "user",
                            "principal_id": i,
                            "permission": "read",
                        }
                        for i in ids[:2]
                    ],
                },
            )
        )
        db = str(cwd / "product.db")
        conf = UpstreamConfig(web, gw, channel, frozenset(ids[:2]), secret, db)
        settings = Settings(db, ids[0], ids[1], channel, Fernet(Fernet.generate_key()))
        api = create_app(settings, Upstream(conf))
        with TestClient(api) as app:

            def login(index):
                u = users[index]
                return app.post(
                    "/v1/login", json={"email": u["email"], "password": u["password"]}
                )

            A, B = [
                {"Authorization": "Bearer " + ok(login(i))["token"]} for i in range(2)
            ]
            assert login(2).status_code == 403

            def state(h):
                return ok(app.get("/v1/state", headers=h))

            def message(h, r, s, t):
                return app.post(
                    "/v1/messages",
                    headers=h,
                    json={"request_id": r, "scope": s, "text": t},
                )

            ok(message(A, "test-private-1", "private", "我不喜欢人多"))
            candidate = state(A)["memories"][0]
            assert not state(B)["messages"]["private"] and not state(B)["memories"]
            ok(
                app.put(
                    "/v1/memories/" + candidate["id"],
                    headers=A,
                    json={
                        "version": candidate["version"],
                        "text": "不喜欢人多",
                        "scope": "shared",
                    },
                )
            )
            ok(message(B, "test-shared-2", "shared", "@AI 周六想出去，预算200元"))
            after = state(A)
            assert [(m["role"], m["text"]) for m in after["messages"]["shared"]] == [
                ("user", "@AI 周六想出去，预算200元"),
                ("assistant", "安静场所"),
            ]
            draft = after["drafts"][0]
            items = draft["items"]
            items[1]["body"] = "周六14:00"
            path = "/v1/drafts/" + draft["id"] + "/confirm"
            ok(
                app.post(
                    path, headers=A, json={"version": draft["version"], "items": items}
                )
            )
            ok(
                app.post(
                    path, headers=A, json={"version": draft["version"], "items": items}
                )
            )
            assert len(state(B)["modules"]) == 2 and any(
                m["body"] == "周六14:00" for m in state(B)["modules"]
            )
            ok(message(B, "test-shared-2", "shared", "@AI 周六想出去，预算200元"))
            assert len(state(B)["messages"]["shared"]) == 2
            released = state(A)["memories"][0]
            ok(
                app.put(
                    "/v1/memories/" + released["id"],
                    headers=A,
                    json={
                        "version": released["version"],
                        "text": "不喜欢人多",
                        "scope": "private",
                    },
                )
            )
            ok(message(B, "test-shared-3", "shared", "@AI 现在呢"))
            assert state(B)["messages"]["shared"][-1]["text"] == "合成回复"
            ok(message(A, "test-private-4", "private", "再次核对"))
            assert message(A, "test-private-5", "private", "限额").status_code == 429
            ok(app.post("/v1/logout", headers=A))
            assert app.get("/v1/state", headers=A).status_code == 401
            assert state(B)["modules"]
            with closing(sqlite3.connect(cwd / "budget.db")) as con:
                assert (
                    con.execute("select sum(used) from daily_budget").fetchone()[0] == 4
                )
            with TestClient(create_app(settings, Upstream(conf))) as restarted:
                restored = ok(restarted.get("/v1/state", headers=B))
                assert len(restored["modules"]) == 2
        print(
            "PASS isolated Open WebUI 0.13.3 + repository gateway + product service: two logins; outsider denied; private chat; authorize and revoke; shared @AI; edit/confirm/idempotency; second session and DB reopen; signout; real gateway quota (4 test calls). Provider responses and usage are fixtures. No paid API call."
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--webui-python", required=True, type=Path)
    parser.add_argument("--gateway-python", required=True, type=Path)
    args = parser.parse_args()
    run(args.webui_python.resolve(), args.gateway_python.resolve())
