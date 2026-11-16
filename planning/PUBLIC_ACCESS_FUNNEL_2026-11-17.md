# 情侣 AI Demo 公网访问（Tailscale Funnel）实施记录

**实施时间：** 2026-11-17 凌晨（CST）
**实施人：** Muse（服务器运维）
**决策：** 用户 2026-11-17 决定执行免费 Tailscale Funnel 方案（此前评估首选 Cloudflare Tunnel + Access，见本地报告 `couple-demo-public-access-plan.md`；本次按用户决定走 Funnel，不部署 Cloudflare、不买域名、零费用）

## 公网访问地址

**https://iz2zecx08mwosw8t20kovoz.tail13b871.ts.net/**

不装 Tailscale 的手机直接用浏览器打开即可，看到 Open WebUI 登录页。

## 做了什么

- 节点已有 funnel 策略权限，无需改 tailnet 策略。
- 执行：`sudo tailscale funnel --bg --yes --https=443 127.0.0.1:4380`
- 原 Serve 配置（443 → proxy 127.0.0.1:4380）在同一地址上转为 Funnel 公开，后端、地址、容器配置均未动。
- 未改 Open WebUI、DeepSeek 网关、SSH 或任何其他配置。

## 测试结果（2026-11-17 凌晨，实施后实测）

- 公网（站外、未加入 tailnet）：HTTP 200，Open WebUI 首页 14,135 字节，`<title>Open WebUI</title>`。
- `/health` 返回 `{"status":true}`，HTTP 200。
- `/api/config` 返回版本 0.13.3；auth 开启，注册关闭（enable_signup=false），登录表单开启（enable_login_form=true）。
- 私网（强制走 tailnet IP 100.127.243.70）：`/health` 同样返回 `{"status":true}`，原私网访问未破坏。
- 容器：`couple-ai-demo-webui-1` 与 `couple-ai-demo-deepseek-gateway-1` 均为 Up 5 小时（healthy），网关 running healthy。
- 账号（只读查库 webui.db）：共 3 个——Demo Admin（admin）、Demo A（user）、Demo B（user），均建于 2026-11-16。账号存在已确认；**实际用密码登录尚未验证**（Muse 不持有密码，需用户或 GPT 侧用真实凭据测一次）。
- 注意：刚开启后第一次公网探测无返回（中继/DNS 约 1 分钟生效延迟），重试后成功。

## 回滚方法

1. 关闭公网入口：`sudo tailscale funnel --https=443 127.0.0.1:4380 off`
2. 恢复原来的纯私网 Serve：`tailscale serve --bg --https=443 http://127.0.0.1:4380`
3. 验证：`tailscale serve status` 应显示 `(tailnet only)`，站外 curl 应不再通。

## 安全提醒（本次未处理，按用户要求只做公网访问）

- 登录页现已暴露给全网，WebUI 密码是唯一一道关；Funnel 本身无前置认证。
- SSH 仍允许密码登录与 root 登录，此前疑似暴露的凭据尚未轮换（独立待办，公网入口前建议处理）。
- DeepSeek 尚未接入（DEEPSEEK_ENABLED=false），网关配额 30 次/天、1024 tokens 上限仍在。

## 待 GPT 复核

- Funnel 路径是否接受（与此前 Cloudflare 首选方案的取舍）。
- 两个 Demo 账号的真实登录验证。
- 是否在公网入口前先做凭据轮换。
