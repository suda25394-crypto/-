# 服务器部署交接｜2026-11-16

> 来源：用户上传的《服务器交接-2026-11-16.md》，生成时间 2026-11-16 21:00（UTC+8）。
> 本文件为脱敏项目状态摘要；刻意删除了明文密码、私钥、密钥值及其他可直接认证的凭据。不要将原始未脱敏交接文件提交到 GitHub。

## 1. 当前结论

**Open WebUI + DeepSeek Gateway 已部署在阿里云 ECS，两个容器均报告 healthy；Tailscale Serve 私网 HTTPS 入口已配置。DeepSeek 真实模型调用尚未启用，因为 API Key 为空且 DEEPSEEK_ENABLED=false。**

这表示服务器底座已运行，不代表真实 DeepSeek 对话、双人手机验收或情侣 AI 功能导演已经完成。

## 2. 服务器环境（交接时实测）

| 项目 | 交接记录 |
|---|---|
| 主机 | 阿里云 ECS |
| 公网 IP | 39.97.234.162 |
| SSH 端口 | 22 |
| OS | Debian GNU/Linux 13 (trixie) |
| 架构 | x86_64 |
| CPU / RAM | 2 vCPU / 约 1.7 GiB RAM |
| Swap | 4 GiB，位于 /swapfile，已配置开机挂载 |
| 磁盘 | 40 GB；交接时约 25 GB 可用 |
| Docker | 29.9.3 |
| Docker Compose | v5.7.1 |
| Tailscale | 已运行；私网地址 100.127.243.70 |

交接时内存记录：used 约 826 MiB、swap used 约 3.3 MiB。该数字是当时快照，不代表当前实时水位。

## 3. 账号与权限（不含凭据）

| 账号 | 用途 | 权限概况 |
|---|---|---|
| root | 维护通道 | 管理员 |
| muse | Muse 运维 | docker 组 + sudo 免密 |
| couple-deploy | Codex 部署 | docker 组 + sudo 免密 |

**重要安全事实**：
- 交接时 SSH PermitRootLogin yes、PasswordAuthentication yes。
- couple-deploy 的密码曾出现在未脱敏交接材料/聊天内容中；之前的部署 SSH 私钥也曾被粘贴到聊天中。相关凭据应视为暴露，不能复制进仓库、工单或新的聊天。
- docker 组成员可控制 Docker daemon，通常等价于高权限；加上免密 sudo，muse 与 couple-deploy 都具有接近 root 的管理能力。它们不是低权限只读账号。
- 尚无证据表明这些凭据已轮换。后续由 Muse 设计并执行安全修复，先确认至少一个可用的替代登录通道，再处理旧凭据与密码登录；不要贸然关闭 SSH 登录导致失联。
- 本文件不保存密码、私钥、API Key、WebUI 初始密码或可用于认证的 token。

## 4. 已部署服务

Compose 项目：couple-ai-demo

项目目录：/home/couple-deploy/app/couple-ai-demo/

| 容器 | 镜像/构建 | 交接状态 |
|---|---|---|
| Open WebUI | ghcr.io/open-webui/open-webui:v0.13.3-slim | healthy |
| DeepSeek Gateway | 本地构建 | healthy |

- WebUI 宿主机只监听 127.0.0.1:4380，未直接绑定公网。
- Gateway 仅在 Docker 内部网络提供服务。
- WebUI 数据卷：webui-data；配额数据卷：budget-data。
- 重启策略：unless-stopped。
- Gateway 资源限制：CPU 0.35、内存 192 MiB、memswap 224 MiB；WebUI 配置 DATABASE_POOL_SIZE=8、UVICORN_WORKERS=1。

## 5. 网络访问现状与产品影响

交接时已配置 Tailscale Serve：

- 私网 HTTPS：https://iz2zecx08mwosw8t20kovoz.tail13b871.ts.net/
- 反向代理到服务器 127.0.0.1:4380。
- 仅同一 Tailnet 内可访问；手机/电脑需要加入同一 Tailscale 网络。
- WebUI 继续保持回环监听，不应为图省事改成 0.0.0.0 或直接开放 4380。

**用户已经明确提出最终体验要求**：伴侣拿到一个手机端软件/桌面图标，点击即可使用，不应要求她先安装或登录 Tailscale。当前 Tailscale 私网入口只是已部署的运维/测试入口，不满足最终伴侣访问体验。公网入口（例如 Funnel、Cloudflare Tunnel 或正式域名 HTTPS）和 PWA/原生应用形态仍待审查与决定；不能把候选方案当成用户已确认技术选型。

## 6. 应用配置状态

交接时 .env 中：
- DEEPSEEK_ENABLED=false
- DEEPSEEK_API_KEY 为空
- DEMO_DAILY_REQUESTS=30
- DEMO_MAX_OUTPUT_TOKENS=1024
- DEMO_PORT=4380
- DEMO_WEBUI_ORIGIN 已对齐 Tailscale 域名
- WEBUI_AUTH_COOKIE_SECURE=true
- ENABLE_SIGNUP=false
- WEBUI_AUTH=true
- WebUI Secret 与 Gateway Token 已生成（不在本文件记录值）

账号初始化标记文件存在，交接方报告管理员与两个用户账号已创建；但管理员凭据是否已安全交付、两部手机是否成功登录，仍需用户实际确认。

## 7. 交接方报告已完成的运维工作

1. 创建 couple-deploy 并配置 Docker 管理权限。
2. 安装 Docker / Compose 并启用 systemd 开机自启。
3. 创建 muse 运维账号并配置管理权限。
4. 配置 couple-deploy sudo 免密。
5. 配置 Tailscale Serve，将私网 HTTPS 代理到 WebUI 回环端口。
6. 确认已有 4 GiB swap，没有重复添加。

以上为交接文件中的记录；后续变更应由最新服务器状态和实际日志再次核验。

## 8. 下一步

1. 先处理已暴露的 SSH/账号凭据风险，并核验管理员账号安全交付。
2. 由 Codex / Muse 分工审查「无需 Tailscale 的伴侣访问」方案，保留现有私网入口，先评估后实施。
3. Codex 检查手机端 PWA 能力、应用图标与启动体验；PWA 与原生 App 选择仍未最终定案。
4. 取得用户明确授权后，在服务器 .env 中配置 DeepSeek API Key，启用真实模型并验证限额与费用保护。
5. 进行两台真实手机测试：账号隔离、共同 Channel、@AI、消息可见性与网络访问。
6. 再开发并验收公开个人档案、关系记忆和 AI 功能导演的跨模块真实闭环。

## 9. 常用运维入口

项目 Compose 文件：/home/couple-deploy/app/couple-ai-demo/compose.yaml

状态：
```bash
docker ps
docker compose -f /home/couple-deploy/app/couple-ai-demo/compose.yaml ps
```

日志：
```bash
docker logs -f couple-ai-demo-deepseek-gateway-1
docker logs -f couple-ai-demo-webui-1
```

重启：
```bash
cd /home/couple-deploy/app/couple-ai-demo && docker compose restart
```

修改 .env 后重建：
```bash
cd /home/couple-deploy/app/couple-ai-demo && docker compose up -d
```

资源：
```bash
free -h && df -h / && docker stats --no-stream
```

> 本文件是交接时点摘要。每次部署或配置变更后，应以新的可复现测试和提交更新状态，不要把历史快照当实时监控。
