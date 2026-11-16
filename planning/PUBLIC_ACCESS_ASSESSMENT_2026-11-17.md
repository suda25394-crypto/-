# 公网访问方案评估｜2026-11-17

> 来源：Muse 运维侧评估报告。检查时间：2026-11-17 00:50（UTC+8）。
> 本文记录评估结论，不代表已实施。评估期间仅进行 SSH 只读检查与官方文档核对，没有修改服务器配置或开放端口。

## 实测现状

- 阿里云 ECS：Debian 13，2 vCPU，约 1.7 GiB 内存及 4 GiB swap。
- Open WebUI 0.13.3-slim 与 DeepSeek Gateway 均在运行且健康；WebUI 仅绑定回环地址，Gateway 仅在 Docker 内网。
- Tailscale Serve 已将现有 HTTPS 地址转发到本机 WebUI，但只允许 Tailnet 内访问。
- Tailscale Funnel 尚未开启；cloudflared 尚未安装。
- WebUI 认证开启、公开注册关闭。DeepSeek 尚未启用，API Key 为空；网关预算为每天最多 30 次、单次输出最多 1024 tokens。
- 交接材料中曾出现服务器 SSH 密码和 SSH 私钥，应视为已暴露；尚未轮换。该事项独立于公网入口部署。

## 方案比较

### 首选：Cloudflare Tunnel + Cloudflare Access

- 新建独立公网入口，不修改现有 Tailscale Serve 私网入口。
- Access 可在 WebUI 登录页前增加邮箱一次性验证码身份校验，仅允许指定的两位用户通过。
- Tunnel 与 Access 免费层可覆盖两人使用；若需稳定自定义域名，需要域名并将 DNS 接入 Cloudflare。临时 trycloudflare 地址仅适合短期测试，不适合作为长期入口。
- cloudflared 尚未安装，尚未部署。

### 备选：Tailscale Funnel

- 可将现有 Serve 服务公网化，保留 Tailnet 内访问，但公网和私网共用同一 ts.net 地址，并非独立入口。
- 没有 Cloudflare Access 式前置身份校验，公网访问者会直接看到 WebUI 登录页，主要依赖 WebUI 强密码和关闭注册。
- 需要先确认 Tailnet 策略允许该节点使用 Funnel；当前尚未核实，也未开启。

## 安全边界

- 不开放阿里云安全组的 WebUI 端口；WebUI 继续只绑定回环地址。
- 不将 SSH 管理端口接入公网应用入口。
- Gateway 不直接暴露公网。
- 实施前核对 WebUI 管理员与两个普通账号的强唯一密码、确认公开注册关闭。
- SSH 密码和私钥暴露史需要单独安排凭据轮换，并确保备用登录方式可用；尚未执行。

## 当前状态与待决事项

**状态：仅完成评估，未实施任何公网入口变更。**

Muse 报告建议选择 Cloudflare Tunnel + Access；Funnel 为低配置成本备选。实施前需要用户明确选择路线。Cloudflare 路线还需确认是否已有可接入 Cloudflare 的域名，以及 Access 允许的两个邮箱；若没有域名，可先用临时地址做短期连通性测试，但不能把它当成稳定交付地址。凭据轮换也需单独安排和授权。

本文件是评估摘要。具体命令、验证与回滚步骤以用户确认路线后由 Muse 制定的实施计划为准。
