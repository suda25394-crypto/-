# Muse 交接 · Android 私人测试版 0.4.0+4

请部署 [Android 0.4 测试发布](https://github.com/suda25394-crypto/-/releases/tag/android-dp-v0.4.0-test.4-r2) 中的 **couple-service-r2-*.zip**，按同页 **SHA256SUMS-r2.txt** 核对 APK 和 ZIP。手机仍用已验证的 25a08a1 安装包，服务修订 2 修复计划确认后集合时间的同步；服务文件名中带实际源码提交。现有公网地址在 11 月 18 日的检查返回产品 schema 1。手机 0.4 需要 schema 3，且模型调用须另有成功回执。

## 准备与回退点

1. 在原部署目录核对 Compose 项目名、产品和网关的镜像 ID、现有网络及卷、两名测试账号与私有频道、原 WebUI 根入口。单独记录预算库当日已用额度。把旧镜像按升级前时间打本地标签，保留现有设置。请只记录这些字段。
2. 在维护窗口用 SQLite 在线备份保存带 WAL 的产品库和网关预算库，再用现行方式备份 WebUI 的频道及数据。沿用产品的会话加密密钥、两个普通账号、频道 ID、产品→Gateway 凭据、原网关独占的官方 Key。备份与密钥仅存运维侧。升级期间暂缓用户写入，先在独立卷用备份副本演练。原 WebUI 和 Funnel 继续工作。
3. 产品容器的在线备份命令见[数据操作](MUSE.md#备份迁移及回滚)。恢复演练用 `python data_tool.py restore <一致备份> <新文件>`，验证完整性和外键。恢复副本会清理旧登录会话。只对升级前的同版本数据库运行旧产品镜像。网关回退继续挂载**当前**预算卷，以记住维护窗口内已消耗的额度。

## 部署两个匹配服务

1. 展开 ZIP，确认含 `services/couple`、`prompts/dp-relationship.zh-CN.md`、`deploy/couple` 和 `deploy/gateway`。用 ZIP 名中的源码提交标记两个镜像。在原 Gateway Compose 项目覆盖实际网关服务的构建目录，保留原网络、别名、端口和预算卷。内部检查原 WebUI 仍能列出 `deepseek-flash`。[网关命令、计费用量及回滚](../gateway/MUSE.md)
2. 产品服务只通过已有网络访问 Open WebUI 和 Gateway。配置 `COUPLE_USER_A_ID`、`COUPLE_USER_B_ID`、`COUPLE_CHANNEL_ID`、`OPENWEBUI_URL`、`GATEWAY_URL`、`COUPLE_SESSION_KEY_FILE`、`DEMO_GATEWAY_TOKEN_FILE`。示例 compose 的内部别名为 `webui` 和 `deepseek-gateway`，请与原别名核对。两边的 `DEMO_DAILY_REQUESTS` 和 `DEMO_MAX_OUTPUT_TOKENS` 沿用现行低值，上限为北京时间每天 30 次、每次最多 1024 输出 token。先确认原配置的 `DEEPSEEK_ENABLED` 和 Key 已通过原有挂载提供给网关，不打印配置值。
3. 在原产品 Compose 项目复用原卷、项目名和身份文件。让 **build context 指向解包的根目录**，Dockerfile 选 `deploy/couple/Dockerfile`，单 worker。进入已核对的运维目录，带上平时相同的 `-p`、`-f` 和 `--env-file` 参数，依次运行 `docker compose config --quiet`、`docker compose build product`、`docker compose up -d --no-deps --no-build product`。请勿将解包出的相对卷或空 secrets 目录作为原环境配置。新进程事务升级 schema 1/2 到 3。
4. 从内部检查 Gateway `/health` 应有 `ok=true`、`app_tools_revision=1`、`upstream_enabled=true`。在产品容器、ECS 回环和公网依次核对产品健康 JSON，应有 `ok=true, schema=3, version="0.4.0+4", service_revision=2, mode="live"`。公网健康路径是既有 `/couple/v1/health`，根路径应仍是原生 Open WebUI。若任何一项不符，停止分发地址，按上节回退或修正。已有产品路径时直接复查原配置。
5. 对照旧版，新服务增加会话工具及附件 `/v1/ai/*`、了解模式与日更档案、共同复盘、集合与变更动态、心愿到回忆的关联、调用回执。健康和成功登录各自独立验收。部分内置多步检索受整轮预算限制，按网关说明执行。首轮只做下列两次模型请求。

## 两次真实调用

先确认当日原额度允许两次，使用与该 APK 配套的产品地址。A、B 在两个独立的 App 会话登录。有实体设备时直接用双方手机。

| 顺序 | 操作 | 要看到或记下的事实 |
| --- | --- | --- |
| 1 | A 私聊发送「请用一句话解释水为什么会结冰。」 | 收到自然语言回答。右上角菜单「调用回执」记录时间、模式、请求及上游报告模型、状态、输入及输出 token。B 无这条私聊。 |
| 2 | B 在共同群发「联调准备好了」。 | A 和 B 都收到，发送方回执显示没有模型调用。 |
| 3 | B 在共同群发「@DP 一天有多少小时？」 | 双方看到相同的**一条** DP 回复，发送方留存第二张回执。并与网关的实际增量核对。 |

上游未返的字段填「未返」。网络中断或费用状态未知先检查回执；首轮失败则回报错误码、发生时间及已用额度。不要用合成回复补齐，也不用额外工具消耗原定的两次调用。

## 用户拿到手机后的点按顺序

两部手机各安装 APK → 关闭 Wi-Fi，使用移动网络 → 在登录页填 Muse 已验证的同一 HTTPS 产品基址及各自普通账号 → 核对两人各自的私聊和共同群 → 一人把共同计划集合点「南门」改为「东门」，另一人点动态查看同一条最新记录，验证「已读」与「同意」分开 → 各自在 Android 设置中强停，再打开 App 检查登录恢复、私聊隔离与计划版本。记录设备系统、网络和各步结果。借助运维端代测或一台模拟器时，请明确保留双真机「待验」。

## 请回给项目所有者

私下发经过手机外网核准的 **HTTPS 产品基址**（保留产品前缀，去掉 `/v1/health`），另附脱敏结果。请勿转发账号密码、密钥、会话或聊天原文。

```text
时间（含时区） / 发布源码提交 / APK 0.4.0+4：
原 WebUI 根路径状态 / 产品公网健康 / schema / build / service_revision：
Gateway 修订 / upstream_enabled / 当日剩余额度是否足两次：
私聊：时间 / 请求模型 / 上游报告模型 / outcome / 输入 token / 输出 token：
普通共同消息：是否零调用：
群 @DP：时间 / 请求模型 / 上游报告模型 / outcome / 输入 token / 输出 token：
两账号是否见同一群回复 / B 是否看不到 A 私聊：
实体手机 A、B 操作结果及网络，或待验：
失败（如有）：步骤 / 错误码 / 是否扣费已知 / 是否回滚：
```
