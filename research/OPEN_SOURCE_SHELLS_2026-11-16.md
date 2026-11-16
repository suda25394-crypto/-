# 现成底座选型调查｜情侣 AI 双人私人 Demo（2026-11-16）

## 状态声明
这是助手基于公开官方材料做的**静态初筛和建议**。**尚未实际安装、压测、改造或验证北京 2 核 2GB 服务器上的可运行性。** 用户尚未确认采用任何一项，禁止将此文称为正式技术决策。

用户目前明确**暂停商业化，优先和伴侣两人私人使用**，但保留「AI 中枢主导/长期理解/多模块联动/双方公开档案/个人 AI 聊天入口/共同三人群聊/小宇宙独立模块」的愿景。

## 主候选 A：Open WebUI（推荐先做最低成本试跑）
- 官方项目 https://github.com/open-webui/open-webui
- 官方 Channels https://docs.openwebui.com/features/channels/
- 官方 DeepSeek/OpenAI-compatible https://docs.openwebui.com/getting-started/quick-start/connect-a-provider/starting-with-openai-compatible/
- 官方 Notes/共享 https://docs.openwebui.com/features/notes/
- 官方性能/低内存 https://docs.openwebui.com/troubleshooting/performance/
- 官方许可 https://docs.openwebui.com/license/

现成：多用户登录、个人 AI 聊天；Channels 多人+AI 共用聊天时间线、实时消息、成员权限，AI 通过 `@model` 触发；OpenAI-compatible API（DeepSeek）；Notes 可授权分享/让 AI 检索编辑；工具/MCP 扩展、内置记忆能力。

重点缺口：真正的「两人先配对」、专门的情侣个人档案/喜好人格问卷、严格确认后更新公开档案、03 环形手机 UI、约会/心愿/小宇宙等 AI 业务模块并不是内置能力；需要 Codex 改造。Channels **默认 AI 不自动回应，需 @模型**；自然群聊的回应行为需要另外设计。聊天与共享档案必须明确区分，不可将对方单独聊天自动写进公开档案。频道工具使用需服务端授权校验。

2GB：官方提供 `ghcr.io/open-webui/open-webui:slim`，不打包本地模型/重型机器学习依赖；可用外部 DeepSeek，SQLite 低内存参数需要调优（`DATABASE_POOL_SIZE=8`、`DATABASE_SQLITE_PRAGMA_CACHE_SIZE=-2000`、`DATABASE_SQLITE_PRAGMA_MMAP_SIZE=0`），关闭非必须 RAG/语音/后台模型任务，先测空闲和实际请求时 RSS。**不保证 2GB 一定稳定**；避免默认全量镜像堆服务。

许可：Open WebUI 当前为含品牌限制条款的许可证，不是纯 MIT/传统 BSD；官方写明 30 日内 50 或更少用户的部署可豁免品牌限制。私人 2 人规模在此区间；如未来重启商业化/扩大人数，应重新审查许可。

## 候选 B：assistant-ui + PocketBase（彻底自定义手机界面的备选）
- https://github.com/assistant-ui/assistant-ui
- https://pocketbase.io/docs/
- https://docs.assistant-ui.com/ （文档入口以实际仓库为准）
- assistant-ui MIT，React 对话组件现成流式输出、工具调用 UI、审批交互和可自定义移动聊天排版。
- PocketBase 带账户、SQLite、权限规则、实时 SSE、文件管理，可承载配对/档案/共同信息；但 API 路由、双人群聊、AI 编排、完整功能模块仍需 Codex 组织代码。
- PocketBase 原 GitHub `pocketbase/pocketbase` 已于 2026-10-26 归档并迁至自有托管；官方文档仍更新。v1.0 前并不承诺兼容，需固定版本、维护备份。
- 优点：UI 和产品体验更自由，避免把重量级通用聊天后台改成情侣 App；缺点：上线速度比直接运行 Open WebUI 慢。

## 其他审过的项目（暂不推荐首选）
- NextChat https://github.com/ChatGPTNextWeb/NextChat ：MIT、轻量 PWA、支持 API；但官方说数据主要保存在浏览器，双人配对+服务端共享聊天不是其默认核心，改造可能并不省工。
- LibreChat https://github.com/danny-avila/LibreChat ：多功能 AI 会话生态；官方标准 Docker Compose 包含 MongoDB、Meilisearch、PostgreSQL/pgvector/RAG，多进程组件对 2GB 小服务器不划算。
- LobeChat https://github.com/lobehub/lobe-chat ：UI 和多模型强，但偏通用 AI Workspace；需更仔细核对部署资源及其 Community License，不能当无约束 MIT 复用。

## 候选验证目标（不等于开发任务已批准）
1. Docker slim + 云端 DeepSeek：能否在北京 VPS 稳定启动、成功调用模型，并留足系统内存。
2. 两个账号各自进入个人 AI 对话：聊天记录是否意外共享（包括 admin 与工具权限）。
3. 建立只有两人参与的 Channel：`@model` 是否可正常回应，能否将回复直接投到频道。
4. 使用两份权限开放的 Notes 暂时代替个人档案：两人可互看，模型只在获得授权后写入，不会泄露私人聊天；注意 AI 访问 Notes 需要启用工具或显式上下文。
5. 评估开发「个人问卷+03 环形首页+AI 功能卡片+小宇宙」是否必须大规模重写 Open WebUI；如是，则停止在 Open WebUI 上做重定制，转用组件库+轻后台。
6. 北京节点私密访问使用合规封闭链路，云端模型费用设硬性预算与故障保护，不公开密钥。

**当前推荐**：Open WebUI slim 作为现成双人 AI 群聊底座进行最小验证；是否正式采用为情侣 App 内核，需通过上述验证后才确定。
