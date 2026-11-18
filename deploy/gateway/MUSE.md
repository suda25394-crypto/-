# Muse · 现有 DeepSeek Gateway 就地升级

本目录从仓库既有网关 `28a1e2653393e35567911677d9646924342d8d77:demo/gateway.py` 延续，保留原 WebUI 所用的 `/v1/models`、`/v1/chat/completions` 和 `/health`。Android 的联网、文件与语音经产品服务调用新增的内部 `/v1/couple-tools/{kind}`。Docker 构建上下文为本目录，依赖锁来自原网关发布。模型仍为 `deepseek-flash`。产品服务、Android APK 与本版 Gateway 需要配套验证。

## 识别现有实例

1. 使用**现有** Compose 项目名、项目目录、Compose 文件以及运维现用的环境文件。先记录 WebUI 根入口状态、当前产品健康回执、网关容器名和镜像 ID。可以用 `docker inspect --format '{{.Image}}' 容器名` 获取镜像 ID；仅按字段查询网络名称及卷挂载目标，避免导出带凭据的完整 inspect 或 Compose 渲染内容。
2. 原仓库 Compose 服务名为 `deepseek-gateway`，容器内端口 8000，预算卷挂载于 `/data`，原预算库为 `/data/budget.sqlite3`。以实际运行值为准。记录现用服务别名、现有网关与产品的共有网络、预算库路径、输出上限和两边较低的每日请求限制。上限为 30 次/北京时间日、1024 token/单次生成，真实网关每项用户操作最多一次模型生成。实际配置更低时继续使用更低值。
3. 在内部运行健康检查。由运维用现有 Compose 参数执行 `docker compose exec -T deepseek-gateway python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=4).read().decode())"`。新版有 `app_tools_revision: 1`；`upstream_enabled` 只说明开关与密钥已由网关加载。旧版不含修订号。

## 备份、验证、切换

- 保留旧镜像 ID，并为其创建带时间的本地回退标签。按现行备份流程将预算库做成**独立新文件**的 SQLite 一致性备份，验证 `PRAGMA integrity_check` 和当天 `daily_budget.used`。另按[产品服务说明](../couple/MUSE.md)备份产品库。保存位置须由 Muse 私下管理。
- 先在隔离测试项目新建**独立**内部网络和临时卷，用合成账号、测试网关凭据、`DEEPSEEK_ENABLED=false` 验证镜像健康和关闭时的提示。常规隔离协议测试运行 `python -m unittest services.couple.tests.test_official_tools services.couple.tests.test_official_gateway -v`，提供端固定为本机合成传输。
- 在原 Compose 项目旁放置运维侧 override，将**既有** `deepseek-gateway` 的 `build.context` 指向本次服务发布包展开后的绝对 `deploy/gateway` 路径，`build.dockerfile` 指向 `Dockerfile`，`image` 设为包含本次发布提交的本地标签。继承原服务的端口、网络、别名、预算卷、环境文件及健康检查。若原服务名不同，应覆盖实际服务名。
- 在原项目目录用原有项目名执行 `docker compose -p "$PROJECT" -f "$ORIGINAL" -f "$OVERRIDE" build deepseek-gateway`。取得运维窗口后执行同参数的 `up -d --no-deps --no-build deepseek-gateway`，只替换该网关。原 WebUI、Funnel、公网根路径与数据使用既有配置。不要用第二个含官方 Key 的网关副本与独立预算库分流生产请求。
- Gateway 独占服务器私下提供的 `DEEPSEEK_API_KEY`。沿用 `DEEPSEEK_ENABLED`、`DEMO_GATEWAY_TOKEN`、`DEMO_BUDGET_DB`、`DEMO_DAILY_REQUESTS` 及 `DEMO_MAX_OUTPUT_TOKENS`。产品服务仅需要其到网关的内部 URL 和已有网关凭据，Android 仅连产品 HTTPS 基址。
- 切换后复查旧 WebUI 根页面、新版健康修订号、相同卷路径及当天预算计数。若原配置超过 Demo 上限，启动会拒绝，按现行批准额度设置后再试。

## 回滚

在同一 Compose 项目将网关镜像引用改回已保存的旧镜像，执行仅针对该服务的 `up -d --no-deps --no-build deepseek-gateway`。沿用当前预算卷，以保留已发生的调用计数。新版仅新增 `app_tool_meter`，旧网关仍读取 `daily_budget`。仅在预算库确实损坏时，按维护窗口的备份恢复流程另行校准当日用量。同步回退产品服务时使用与旧 schema 对应的产品库备份，避免用旧程序读取新版产品库。

## 真实模型与费用回执

先从授权的两个 Android 测试会话登录新版产品服务。一条私聊短问题、一条共同群普通消息、一条共同群 @DP，核对普通消息无模型调用、两人看到相同群答复。首轮勿顺带发起联网、文件或语音操作。公网上报仅包含提交、北京时间、网关修订号、产品 schema、模型、调用状态、实返输入/输出 token 和双账号群回复是否一致。用户标识、聊天正文、地址、密钥及日志原文留在运维侧。健康、真实推理、双实体手机各记一栏。产品凭据或 Key 已存在本身不能代替一次完整响应。

- 所有收费操作共享原子 `daily_budget`；常规对话、独立工具、文档解析上传和随后提问均经过同一张表。解析上传与模型提问分别占一次，临时文件删除不占次数。App 的本地预览、手工编辑、普通共同消息和确认业务草稿不调用模型。
- 网关 `app_tool_meter` 只存 UTC Unix 时间、能力、计量单位、数量、估算费用、提供端 usage；不写请求正文或密钥。按 `unit='model_tokens'` 的 `usage` 查普通对话及应用工具的实际计量。高审拒答、断流或超时可能有账单；无法确定用量时标记 `unsettled` 并保留预算占用。产品请求号去重，未知扣费状态不自动重发。
- 2026-11-18 北京时间 12:00 起，模型自带的联网搜索/抓取按 token 计量。独立 Search、Fetch 每次成功请求估算 0.005 元；成功 OCR/文档解析每页 0.0015 元。ASR 记录返回时长并按秒估算，限时价每小时 0.39 元；TTS 记录计费字符（汉字计二，其他字符计一），限时价每万字符 1.5 元。对账使用服务器当天官方账单与实际时段。[官方计费](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/)
- 部分 Files 上传回执仅返回文件标识、不含页数。这时 `pages.quantity` 和 `cost_cny` 为 null，`settlement=provider_required`；与提供端账单对账。不能将“缺字段”当作零费用。官方模型工具的 `max_tokens` 按推理步骤生效。Responses 的 `max_tool_calls` 被忽略，Flash 的内置联网工具没有文档保证的 `max_uses` 或整轮 token 限制。深度搜索描述的约 20 次也不是硬上限。[官方 Chatbot 协议](https://api-docs.deepseek.com/zh-cn/guides/build_a_chatbot/) · [联网工具](https://api-docs.deepseek.com/zh-cn/guides/web_tools/)

## 现行额度下的可用范围

| 手机操作 / kind | 生产 Gateway 的上游路径 | 北京时间当日预算 |
| --- | --- | --- |
| 网页搜索并回答 `web`、阅读链接 `read_url` | 首次使用独立 Search 或 Fetch，记录公开资料，再请求一次关闭模型内置工具的 Flash。两项额度在取资料前原子预留。 | 首次 2 次，其中独立接口计费 1 次；同来源追问只占 1 次模型生成 |
| 独立 `search`、`fetch` | 直接固定工具接口，返回摘要或正文及来源。 | 每次 1 次，无模型输出 |
| `deep_search` | 对同一个公开词独立检索一次，再开启思考模式做一次总结。供应端自主多轮深搜仅有合成验收。返回 `search_mode=single_lookup`，同来源续问返回 `same_source`。 | 首次 2 次；同来源追问 1 次 |
| `image_search` | 官方以图检索只能通过内置联网。供应端内部循环目前不能核实整轮上限。收费前返回 `multistep_budget_blocked`。 | 0 次 |
| `vision`、`poster_draft`、`title`、常规聊天 | 一次生成，关闭内置工具。适用输入输出及图片审查为 high。标题随本轮生成，官方说明标题本身免费。 | 每次 1 次 |
| `parse_text`、`parse_rich` | 先建立有到期时间的文件，再做一次有上限的模型回答。两次额度在传文件前原子预留。 | 每项 2 次；页数另记。清理文件不占额度 |
| `ocr`、`asr`、`tts` | 直接调用官方独立端点。 | 每次 1 次，无模型输出 |

真实网关 `/health` 会显示 `native_multistep:false`、`bounded_web:true`。无需添加环境开关。只有注入本机 HTTP MockTransport 的合成协议测试可启用原生四类多步工具，覆盖签名内容块原样续问。原生搜索能力不会通过生产环境开关意外放行。代码拒绝为真实传输启用该测试选项。正式放开须有新的整轮硬上限证据或产品方另行批准预算。来源追问复用原会话已授权的公开资料，本轮可对选择的来源继续提问；模型未获得新一轮联网权限。模型输入/输出、可得的缓存命中分项和 safety_tokens 取实际 usage。安全审核 token 已包含在输出用量中，测试验证超出上限时完整结果被扣留；供应商没有提供独立的审核费用封顶参数。[官方安全审核与计费](https://api-docs.deepseek.com/zh-cn/guides/safety/)

模型用量来自网关实际回执，账单金额由服务端时段和供应商对账确定。

## 文件、检索与流式安全

- 产品附件限定原配对、会话范围与模块，加密暂存一小时并允许上传者提前删除；ASR 原音及待修订转写只给上传者。清理会关闭待确认的海报草稿。图片理解使用内联图像，OCR 与 ASR 直接向固定工具端点提交文件。PDF/Office 需要官方文件解析时显式传 `expires_after[anchor]=created_at` 和 `expires_after[seconds]=3600`，完成/失败后均尝试立即删除；调用中途机器断电仍由上游 TTL 接管。[Files API](https://api-docs.deepseek.com/zh-cn/guides/files_api/) · [文档解析](https://api-docs.deepseek.com/zh-cn/guides/document_parsing/)
- 独立 Search 只送公开关键词，不附原始聊天、用户画像、IP 或位置；阅读目标预先核验协议、主机和 DNS 结果。私网 IP、内网、回环、凭据型查询、含用户密码的 URL 均不作为公开来源。远端网页抓取由官方固定接口完成，用户链接不作为产品服务的任意 HTTP 代理。[Search 与 Fetch API](https://api-docs.deepseek.com/zh-cn/guides/search/)
- 合成环境中的原生联网协议使用 Messages API 的服务端工具；同一授权会话中原样重放带签名的工具内容块，在手机端只展示正文、公开来源、可选标题。图片搜索经内置联网执行。独立 Search 只支持网页。向 DP 提交的输入输出使用 `safety_check.level=high`；适用图像、富文档裁图纳入模型审核。模型结果收到终态后才交给用户或生成草稿，拒答、工具错误、截断和 SSE 中断均保留失败状态。[联网工具](https://api-docs.deepseek.com/zh-cn/guides/web_tools/) · [模型内容安全](https://api-docs.deepseek.com/zh-cn/guides/safety/)
