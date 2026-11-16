# 情侣 AI 私人 Demo｜阶段 1

使用锁定镜像的 Open WebUI 提供账号、各自的 AI 聊天与共同频道。模型入口显示为 **AI**，通过专用网关调用 DeepSeek 官方 `deepseek-flash`。

## 准备与启动

在已审计且获准部署的 Docker 主机上进入本目录。现有服务和数据卷请保持独立。首次启动前检查磁盘、端口、备份与容器内存余量。

1. 复制 `.env.example` 为 `.env`，文件只授予部署账号读取权限（Linux 使用 `chmod 600 .env`）。用 `openssl rand -hex 32` 分别生成两个随机值，填入 `WEBUI_SECRET_KEY` 和 `DEMO_GATEWAY_TOKEN`。保留两者以便重建容器。
2. 使用默认的 `DEEPSEEK_ENABLED=false` 启动。保留回环监听。若使用经过授权的私网 HTTPS，设置 `DEMO_WEBUI_ORIGIN` 为完整访问源，保留安全 Cookie；若仅在本机通过 HTTP 调试，可在该测试实例中设 `WEBUI_AUTH_COOKIE_SECURE=false`。
3. 运行 `docker compose config --quiet`，然后运行 `docker compose up -d --build`。以 `docker compose ps`、`docker compose logs --tail 80 webui deepseek-gateway` 查看状态。本机默认访问 `http://127.0.0.1:4380`。远程主机初始设置可用获授权的 SSH 回环转发，例如 `ssh -N -L 4380:127.0.0.1:4380 USER@HOST`。
4. 首次访问空实例创建管理账号。进入 Admin Panel → Users，由管理员各添加一个角色为 **User** 的账号。首个管理员建立后，开放注册关闭。两人日常使用各自的普通账号。在 Admin Panel → Models 找到 **AI**（`deepseek-flash`），打开 Access，给这两个账号 Read 权限并保存。
5. 用 A 登录，侧边栏 Channels 的添加入口选择 **Group**，成员只选择 B。检查群详情里恰好两位成员。两人通过 **AI** 模型各自开私聊，在群中输入 `@AI` 时从提及菜单选中 **AI**。模型回复默认出现在共享消息的线程中。

管理员账号用于运营；宿主机、容器和数据库备份访问仍属于有权读取底层数据的运维权限，须限制访问。群成员和账号权限由 Open WebUI 管理。伴侣双方的账号密码各自保管。

## 授权开通真实 DeepSeek

将 DeepSeek 专用密钥填入服务器权限受限的 `.env`，设置 `DEEPSEEK_ENABLED=true`，执行 `docker compose up -d deepseek-gateway`。密钥仅注入网关。Open WebUI 使用独立网关令牌。真实聊天文本会由配置的 API 处理；部署验收用合成文本。

- 默认全实例每天最多 **30 次**上游尝试，北京时间零点切换计量日期。网关在调用前原子占用额度，失败或中断的请求也计入，避免重复或并发请求绕过。
- 每个请求最多 **16 KiB** JSON，对话包含文本历史；输出默认最多 **1,024 tokens**，关闭思考。超过输入限制时可以缩短信息或开启新会话。额度是请求次数与输入/输出上限，DeepSeek 钱包扣费由供应商按实际用量结算。
- 网关日志记录请求计数、输出上限、返回的 token 计数及失败类别。请求正文、密钥和供应商错误正文不写入网关日志。禁用、超限、错误时返回明确失败。
- 线上 .env、数据库和备份按敏感数据管理。共享检查记录时使用匿名账号并脱敏。避免使用会打印变量值的 `docker compose config`。

## 验证与回滚

本地网关回归与原生接口权限测试：

```text
uv sync --locked --no-install-project
uv run --locked --no-sync python -m unittest discover -s tests -p "test_*.py" -v
uv run --locked --no-sync python tests/verify_webui.py --fresh-local-test http://127.0.0.1:4380
```

最后一条会在**空白的一次性 WebUI 实例**创建测试账号、聊天和频道，启动前使用独立测试卷、端口和禁用模型配置。它校验原生 API；可选 `--browser-executable /path/to/chrome` 使用装有 Playwright 的测试环境开启两套带触控模拟的手机浏览器会话。离线流式端到端测试可让空实例的 OpenAI-compatible 连接指向下述专用测试进程，测试进程须使用独立的 SQLite 路径与令牌。

```text
uv run --locked --no-sync python -m uvicorn --app-dir tests deepseek_fixture:create_fixture_app --factory --host 127.0.0.1 --port 4381
```

为测试进程设置 `DEEPSEEK_ENABLED=true`、`DEEPSEEK_API_KEY=fixture-only`、`DEMO_GATEWAY_TOKEN` 和独立的 `DEMO_BUDGET_DB`。将测试实例的 OpenAI-compatible 地址设为能访问该进程的 `/v1`，再运行 `verify_webui.py` 并附上 `--fixture-reply "OFFLINE TEST FIXTURE."`。同时指定 Chromium 可执行文件时，第一个会话会触控点选 `@AI` 并发送，两个会话都会在不刷新页面的情况下点开同一回复线程。部署镜像排除了测试代码。

现场验收使用两个独立浏览器会话及两部手机。先确认私网 HTTPS 的服务地址仅允许指定成员到达，然后保留以下证据：

1. A、B 各发一条不同的合成私聊；从另一方历史和详情链接均不能读取。检查新注册被拒绝。
2. A、B 在共同群分别发消息。从其中一方发送 `@AI` 加无隐私的测试请求，两部手机都能打开同一回复线程。
3. 用额外测试账号或隔离验收实例确认非成员看不到频道、直接访问链接和发消息均失败。生产实例保留两个普通账号。
4. 记录空闲与同时聊天时的内存峰值、`docker stats --no-stream` 样本、主机 RAM/Swap、容器重启次数、日志时间和模型 token 统计；如内存逼近 2 GiB，先以实际证据调整。确认关闭 DeepSeek 时产品清楚显示无法调用。

暂停可用 `docker compose stop`；恢复用 `docker compose up -d`。版本回退使用旧镜像与其兼容的数据备份。数据目录由项目卷 `webui-data`、`budget-data` 保存；重建容器前安排备份，保留原始卷和相同的会话密钥。

[阶段记录](../planning/PROGRESS.md) · [Open WebUI Channels](https://docs.openwebui.com/features/channels/) · [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)
