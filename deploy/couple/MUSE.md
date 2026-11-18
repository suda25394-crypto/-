# Muse 部署交接 · Android 私人 Demo

生产部署负责人为 Muse。以下为已有两个普通账号及私有频道增加一个独立业务服务。安装包登录页填写产品服务地址。原生 Open WebUI 的首页地址由现有用户继续使用。

## 交付内容和运行条件

- 服务入口 `services.couple.api:app`，每实例一个 worker。容器内端口 8787，主机只绑定 127.0.0.1。数据库位于独立卷 /data，SQLite WAL，启动会创建 schema 1；遇到更高版本拒绝运行。
- Compose 使用既有 WebUI 和 Gateway 共享的外部 Docker 网络，通过服务名称调用。先核对实际服务名、网络、镜像版本、频道 ID 和两个账号 ID。WebUI 适配基准为 0.13.3。若实际 DNS 别名有差异，调整 OPENWEBUI_URL 和 GATEWAY_URL。
- 源码包的根目录含 services、deploy；Compose 的 build context 相对 deploy/couple 指向根目录。生产镜像仅复制服务 Python 文件，排除测试夹具、APK 和密钥。Dockerfile 固定 Python 基础镜像摘要和依赖散列，限定 Linux x86_64。构建时需要到官方镜像及 Python 包源的出站网络。先记录主机剩余磁盘、内存、现有容器健康和公网根路径状态。
- 产品私聊与业务数据位于产品库。共同消息保存在既有频道；产品保存上游回执用于归属确认和失败重试。恢复要同时考虑两个存储的时间点。安装包持有产品会话，服务端暂存的上游用户令牌经 Fernet 加密。

## 位于服务器的配置

在 deploy/couple 从 .env.example 创建本机 .env。PRODUCT_IMAGE_TAG 填交付清单中的源码提交；COUPLE_USER_A_ID/B_ID 填两个不同的普通用户 UUID；COUPLE_CHANNEL_ID 填指定私有频道，WEBUI_DOCKER_NETWORK 填已存在的网络。账号 ID 和频道 ID 由 Muse 在服务器私下确认。两名账号通过配对检查后才能进入。频道成员变化应重新验收。

secrets/session.key 使用服务器上新生成的 Fernet 密钥，例如在安全目录由 Python 写入 `base64.urlsafe_b64encode(os.urandom(32))`；secrets/gateway.token 由 Muse 从既有 Gateway 秘密来源安全挂载或写入，两个文件均须容器用户 10001 可读。目录仅部署账号和容器可读，文件权限建议 0400，私下备份钥匙。DeepSeek 的真实 API Key 只放在已有 Gateway；客户端与产品服务均无需这一密钥。配置项示例只含空占位。

## 启动与验收

在 deploy/couple 执行：

```sh
docker compose config --quiet
docker compose build product
docker compose up -d product
docker compose ps
curl -fsS http://127.0.0.1:8787/v1/health
```

健康回执应有 ok=true、schema=1、mode=live。live 表示生产适配器已加载，模型是否启用由一次实际请求单独核实。在更新 HTTPS 路由前保存本机当前 Funnel 状态。原项目使用 443 根路径代理 Open WebUI。经运维授权，可按当前 tailscale 版本的 --set-path 为产品增加单一路径，例如：

```sh
tailscale funnel status
sudo tailscale funnel --bg --https=443 --set-path=/couple http://127.0.0.1:8787
```

从公网检查原根路径和 `https://已有Funnel主机/couple/v1/health`。要看到产品健康 JSON；HTML、404 或身份不符应停止交付登录地址，并核对路径前缀转发。App 服务地址填写 `https://已有Funnel主机/couple`。若采用现有反向代理，配置只将 /couple/ 下的请求去掉该前缀后转给回环端口。避免输出请求体、Authorization 或长期保存明文聊天日志。[Funnel 路径配置](https://tailscale.com/docs/reference/tailscale-cli/funnel)

1. 让 A/B 在各自手机输入自己现有账号密码。首次发布前检查登录、重开恢复、退出、频道成员身份以及重新登录。保留失败回执时只记状态和错误码。
2. 按既有授权在 Gateway 私下配置密钥及 DEEPSEEK_ENABLED。保持 deepseek-flash 白名单、DEMO_MAX_OUTPUT_TOKENS ≤ 1024、DEMO_DAILY_REQUESTS ≤ 30；产品配置取相同或更低值。先测试关闭模型时的错误，再由 A 发起一次私聊、群中一次 @AI，记录时间、真实模型、状态、token 计数。未批准费用时保持停用。
3. A 私聊写「我不喜欢人多」，B 查询时应无候选。A 分享后由 B 群聊 @AI 询问周六预算 200 元；在草稿中修改时间、确认后，A/B 查看同一记录和版本，重复点击应只有一份。A 纠正或撤回后新上下文应变化。另测私下惊喜、取消草稿、移动网络切换和重开。
4. 观察产品容器、WebUI 和 Gateway 的实际内存、磁盘、延时与错误率，记录真实结果。产品前台会轮询状态；待机时客户端暂停轮询。统计调用与 token 可按日期聚合 usage 表的 outcome/in_tokens/out_tokens；勿复制 input/output/session 字段。

## 备份、迁移及回滚

首次安装从空产品卷初始化，无需导入两个账号密码或迁移 WebUI 表。每次升级先备份。服务运行时用 SQLite 在线备份读取包括 WAL 的一致快照。示例命令均在 deploy/couple 目录：

```sh
docker compose exec -T product python /app/data_tool.py backup /data/product.sqlite3 /data/pre-upgrade-UNIQUE.sqlite3
docker compose cp product:/data/pre-upgrade-UNIQUE.sqlite3 ./backups/pre-upgrade-UNIQUE.sqlite3
```

先创建仅运维可读的 backups 目录。每次使用新名字，异机加密保存备份，并遵循现有流程另备 Open WebUI 的数据卷、频道、Gateway 预算库和会话加密密钥。快照含私人内容。例行恢复演练可用只读备份为源，运行 `python data_tool.py restore 备份 新路径`。工具验证 schema、完整性和外键，恢复副本中清除登录会话。Muse 在维护窗口停止产品写入，再把通过验证的恢复副本作为新的 COUPLE_DB 指向；原数据库与 WAL 一起留存。数据库为产品、频道为 WebUI 所有，需核对恢复点后的频道写入和模型额度，避免盲目重放。

代码回退优先恢复旧镜像标签加兼容的产品数据库；首次部署回退只需移除产品路径并停产品服务。仅在采用上述路径配置时使用：

```sh
sudo tailscale funnel --https=443 --set-path=/couple off
docker compose stop product
```

确认原 WebUI 根路径、原私网入口和 Gateway 仍正常。历史 SSH 凭据轮换沿原运维待办处理。此交接文件没有执行云端操作。
