# 私人 Demo 资源复用审计

更新于 2026-11-16。按当前实施阶段补充。版本和来源为实际检查所得，验证范围见最后一列。

| 资源与来源 | 版本与许可 | 解决的问题、兼容与成本 | 权限与最小验证 | 选择 |
|---|---|---|---|---|
| [Open WebUI Slim](https://github.com/open-webui/open-webui/releases/tag/v0.13.3) · [许可](https://docs.openwebui.com/license/) | v0.13.3，源码 `b0e6098e940942281d9c83f3529ea117287a3a22`，镜像索引 `sha256:8faf917243afee55e042b10ddc08ed6ae6fa9c62522c7e14d81e7cf2922325ae`。Open WebUI License 含品牌条款和小规模豁免。 | 原生认证、私聊、共享 Channel、OpenAI-compatible 客户端。复用原 UI，不加本地模型或向量数据库。2 GiB RAM 是否够用待测。 | GHCR 实读 linux/amd64 和 linux/arm64 索引；核对固定版本的 Channel 模型触发路径、显式成员校验与管理员读聊配置。实机未启动。 | 采用既定底座。 |
| [DeepSeek 官方 API](https://api-docs.deepseek.com/) · [请求参数](https://api-docs.deepseek.com/api/create-chat-completion) | `deepseek-flash` 服务标识，厂商托管服务，按其 API 价格与条款。 | 一套 OpenAI-compatible 服务用于私聊和群聊。关闭思考模式，先限制文本请求体、输出和请求量。 | 核对官方模型名和 API 说明；未使用密钥、未发起生成请求。调用会在 DeepSeek 处理授权聊天文本。 | 阶段 1 接入目标。 |
| [LiteLLM](https://github.com/BerriAI/litellm) · [预算说明](https://github.com/BerriAI/litellm-docs/blob/main/docs/proxy/budget_fallbacks.md) | 官方文档 main，未选发布版本，未完成对应版本许可复核。 | 检查虚拟密钥、预算和路由功能。账后拒绝机制和完整代理配置超出了单模型、两账号的需求。 | 只读核对文档。未安装、未给密钥、未运行。 | 阶段 1 不引入。 |
| [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve) | 官方托管控制面及客户端；未选版本或套餐。 | 可将回环端口通过私网 HTTPS 提供给指定设备；北京节点与两部手机网络实测、既有私网及使用条件待核实。 | 查阅官方 Serve 与访问控制文档；未登录、未安装、未连接。 | 候选，需要先核验既有私网和授权。 |
| 本机 Agent Reach、增量实施、安全加固、代码审阅；Git 与 Git Credential Manager | Agent Reach 本地 skill；其余实施技能来自已装 agent-skills 0.6.16；Git 2.54.0.windows.1。 | GitHub 官方仓库核对、分阶段验证和访问控制检查。本机已具备，无需另装插件。 | 读到本地技能、检出项目、Git 远端读取和推送 dry-run 成功。GitHub CLI 未登录，现有 Git 凭据可用。 | 采用现有能力。 |

## 阶段 1 执行补充

| 资源与来源 | 版本与许可 | 解决的问题、兼容与成本 | 权限与最小验证 | 选择 |
|---|---|---|---|---|
| [FastAPI](https://github.com/fastapi/fastapi)、[HTTPX](https://github.com/encode/httpx)、[Uvicorn](https://github.com/Kludex/uvicorn)、Python 标准库 SQLite | FastAPI 0.163.1 MIT、HTTPX 0.28.1 BSD-3-Clause、Uvicorn 0.54.0 BSD-3-Clause，PyPI 元数据实读；Python 运行镜像固定到 3.12.13 Slim 的登记索引。 | 复用 ASGI、HTTP/SSE 客户端和原子事务。只增加一个无外部数据库的模型网关，补足前置用量限制。 | 8 项单测、实际 HTTP 禁用态、Open WebUI 接入与离线 SSE 均通过；网关锁定依赖 pip-audit 未报告已知漏洞。真实密钥与供应商响应待验。 | 采用。 |
| [Compose Specification](https://github.com/compose-spec/compose-spec) | Schema `3a4a6995e4a971f6173dff9130cb3e38e6738651`。 | 复用官方 Schema 验证部署声明。 | 本机 Schema 校验通过。Docker CLI 和 Linux 运行仍待验证。 | 采用。 |
| [Playwright](https://github.com/microsoft/playwright-python) | 1.65.2。 | 隔离浏览器会话，测试实际登录与共同频道；仅安装进本机临时测试环境。 | 两个独立浏览器上下文使用合成账号，390×844 页面对话可读。 | 采用为验收工具。 |
