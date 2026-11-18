# 服务端上游契约与本机联调回执

适配对象是 Open WebUI 0.13.3 普通用户接口与本项目现有单模型 Gateway。Android 使用产品令牌。产品服务持有加密保存的 WebUI 用户会话；网关凭据单独留在服务端。服务端创建每次独立的 HTTP 请求，关闭系统代理、自动跳转和自动重试，分别处理登录、模型关闭、超时与额度耗尽。

## Muse 的配置

| 配置项 | 说明 |
|---|---|
| `OPENWEBUI_URL` | Open WebUI 的内部源地址，例如 `http://webui:8080`。使用与现有容器连通的专用网络。 |
| `GATEWAY_URL` | 网关的内部源地址，例如 `http://deepseek-gateway:8000`。填写到端口即可。 |
| `COUPLE_USER_A_ID`、`COUPLE_USER_B_ID` | 两个不同普通账号的 WebUI 用户 ID。 |
| `COUPLE_CHANNEL_ID` | 双方所属私有 group 频道的 ID。详情接口必须返回与 A/B 恰好一致的两个成员。 |
| `COUPLE_DB` | 产品数据库；频道消息的投递回执和幂等记录也存储于此。 |
| `DEMO_GATEWAY_TOKEN_FILE` 或 `DEMO_GATEWAY_TOKEN` | 与现有 Gateway 匹配的服务端凭据；优先用只读秘密文件，文件优先于环境变量。 |
| `DEMO_MAX_OUTPUT_TOKENS` | 默认 1024；产品允许 1–1024。与 Gateway 的实际限制核对。 |
| `DEMO_DAILY_REQUESTS` | 由产品业务层按北京时间日期计数，默认 30；Gateway 对包括原生 WebUI 在内的所有调用再统一计数。部署前核对两个进程的实际配置。 |

上游连接须使用受控的容器网络或 HTTPS。DeepSeek 提供商密钥只交给已有 Gateway。产品检查现有普通账号获准使用 `deepseek-flash`，并向 Gateway 发起固定、非流式的请求。生成使用产品层传入的授权档案、记忆、模块、当前范围对话与反馈。16 KiB 是网关对整个 JSON 请求体的上限；当背景过长时逐项缩减，对仍然超长的单条输入返回 413。

## 核对过的接口

| 路径 | 使用方式 |
|---|---|
| `POST /api/v1/auths/signin`、`GET /api/v1/auths/`、`POST /api/v1/auths/signout` | 普通账号密码登录、按 Bearer 实时核对本人身份、注销会话。被选账号须为 `role=user`。 |
| `GET /api/v1/channels/{id}` | 当次取得 `id/type/is_private/user_ids`；归档、删除、成员变化、用户失权均会拦截访问。 |
| `GET /api/v1/channels/{id}/messages`、`.../messages/{parent}/thread` | 同步最近 50 条主消息及其中各线程最近 50 条回复，并按时间顺序展示。完整频道历史保存在原生 WebUI。 |
| `POST /api/v1/channels/{id}/messages/post`、`GET .../messages/{id}/data` | 用户身份写入真实频道。产品生成的回复在原生频道显示「AI ·」，产品依据数据库中的远端消息 ID、作者和内容摘要标识回复。用户自己输入同样前缀仍为用户消息。原生模型线程沿用服务器提供的 `meta.model_id`。 |
| `GET /api/models` | 检查当前用户的模型授权。 |
| `GET /health`、`POST /v1/chat/completions`（Gateway） | 运维核对 `upstream_enabled`；发送请求，读取返回的提示、输出 token 计数。供应器开关、每日 30 次、每次最多 1024 个输出 token 由部署方复核。 |

WebUI 自行分配消息 ID。产品在上游写入前持久化唯一回执；超时后相同请求只查询频道和数据标记进行对账。近 250 条内仍无法确认时返回 `delivery_unknown`，由 Muse 通过两方渠道记录核对，保留原请求号。产品会将 WebUI 原生的模型/应用提及语法显示成普通文本，以避免产品生成一遍后原生频道再次触发。原生界面自行发起的模型对话继续遵循原生处理方式。Android 私聊历史由产品服务按本人隔离持久化，原生 WebUI 既有个人聊天档案仍在原位置。

## 可复现验证

在仓库根运行：

```powershell
python -m unittest services.couple.tests.test_upstream -v
python -m services.couple.tests.native_smoke --webui-python '已安装 Open WebUI 0.13.3 的 Python 路径' --gateway-python '已安装网关依赖的 Python 路径'
```

第二条命令要求执行侧具备产品服务依赖、PyYAML、Git 以及本地 Git 中的 Gateway 提交。脚本只选择新的回环端口和临时目录，生成合成账号与短期密码。它会启动真实的 Open WebUI 后端以及指定提交的 Gateway；模型提供商的 HTTP 传输被固定为本地测试回包。结束后关闭子进程并清理临时数据。

2026-11-18 本机 Windows 实测完成：

- 独立合成普通账号 A 和 B 登录。第三个普通账号被拒绝，A 的私聊和未确认候选在 B 的读取得到空集合。
- A 发布「不喜欢人多」，B 在共同频道发 `@AI`。测试提供端实际收到获准背景；双方读取到同一条回帖与可编辑草稿。
- 确认前修改日程为「周六14:00」；重复确认只写入约会和日程各一条，B 重开产品服务和 SQLite 后仍然读取相同版本。
- A 撤回该偏好，后续发送给测试提供端的背景也移除了它。验收包含登出后的产品令牌失效、相同请求重复发送、真实 Gateway SQLite 的计数。为用少量请求覆盖上限，测试实例明确配置为 4 次，4 次后第 5 次被网关拒绝。
- 契约测试额外覆盖上游接收后响应丢失的对账、无法确认时停止重发、消息角色伪装、双人频道成员变化、关闭模型与超额。当前生产环境真实模型调用、生产用量、真实用户及双手机不在以上回执范围内，需 Muse 和两位用户联调。

上游依据为 [WebUI 身份路由](https://github.com/open-webui/open-webui/blob/v0.13.3/backend/open_webui/routers/auths.py)、[频道路由](https://github.com/open-webui/open-webui/blob/v0.13.3/backend/open_webui/routers/channels.py)、[消息模型](https://github.com/open-webui/open-webui/blob/v0.13.3/backend/open_webui/models/messages.py) 与 [本项目 Gateway 固定版本](https://github.com/suda25394-crypto/-/blob/28a1e2653393e35567911677d9646924342d8d77/demo/gateway.py)。
