# 情侣 AI 专属前端 V1｜实施记录

日期 2026-11-17。以 GitHub `main` 的 `8ddca9f` 为基线，分支 `codex/couple-frontend-v1`。本条记录随前端提交。

## 交付和设计

- [可运行项目](../frontend/README.md)以 V0.6 的 03 方案为参考。浅色、中央单一 AI 入口、环形功能节点、底部导航。首页仅有四个关联模块节点，功能目录容纳完整的十二项。小宇宙通过 `#/universe` 独立进入。
- `frontend/src/data.js` 维护模块和档案种子数据，`director.js` 维护演示规则，`services.js` 实现界面调用的数据边界。页面视图只读接口和提交意图。独立 routes 支持浏览器前进、后退与刷新。
- 两个合成演示身份分别有个人 AI 入口，共同空间的消息和 `@AI` 草稿在两个本机身份间可读。个人草稿在当前演示身份下可见。程序不会把个人对话复制进共同频道或档案。每人可通过表单编辑自己的双方可见档案；推测偏好经本人逐条点击确认才添加。
- 模块草稿可以查看、编辑和确认。确认页区分个人演示版本、共同版本和可选记忆。选择共同保存须经过确认，两种已保存版本可以分别查看。五维人格卡显示尚未测量，文字画像使用合成自述，后续测量和授权范围依据既有规范复核。
- 复用资源包括 V0.6 的环形布局与主题、原生 ES Modules、`<details>` 展开和 `<dialog>` 确认、现有 Playwright/Chrome 测试环境。轨道、星球、图形卡及线性图标由本版实现，基础 CSS 和 HTML 即可运行。未引入额外框架或在线素材服务。 [对话框](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog) · [减弱动态效果](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-motion)

## Open WebUI 接入评估

已核对仓库锁定的 Open WebUI 0.13.3 源码与接口。只读检查现有公网 `GET /health` 和 `GET /api/config`，服务健康，版本 0.13.3，认证开启、公开注册关闭。当前前端使用浏览器本地适配器；生产服务没有参与试用数据和测试写入。

| 能力 | 0.13.3 核对点 | 接入建议 |
|---|---|---|
| 账号会话 | `POST /api/v1/auths/signin`、`GET /api/v1/auths/`、`POST /api/v1/auths/signout`。登录返回会话数据，原生会话可使用 Cookie。 | 先在隔离实例验证同源会话适配层。复用各自的 Open WebUI 用户帐号。服务端持有每位用户自己的上游会话，浏览器只接收必要的用户字段和有时限的 HttpOnly、Secure、SameSite 会话 Cookie。修改请求校验来源与 CSRF，退出时清除并撤销会话。 |
| 个人聊天 | `/api/v1/chats` 管理自己的聊天；`POST /api/chat/completions` 走原模型链路。携带会话标识时可能走 WebSocket 路径，简单流式请求与持久化聊天应分别验证。 | 用普通用户会话转发经过允许的接口。未确认的产品可见性规则由后续决策确定，保留当前隔离测试。 |
| 共同空间 | `/api/v1/channels/{id}/messages`、`POST …/messages/post` 和 `…/{message_id}/thread` 复用成员权限和共同线程。原生模型提及可触发频道回复。 | 服务端验证成员和频道，前端拿允许的消息字段。先跑通双账号 HTTP 收发，再验证实时 WebSocket；复用同一个模型网关。 |
| 档案与导演 | 配对关系、用户确认、人格证据、模块版本属于产品业务。Open WebUI 提供聊天和模型能力。 | 暂以 `services.js` 接口隔离页面；接入后端时从会话推导用户和配对关系，校验所有者、读取范围、确认与版本，将经过授权的结构化资料用于生成。 |

同源适配层仅代理需要的用户接口，避免任意路径与管理员接口。上游管理员凭据、DeepSeek API Key 和网关内部令牌留在服务端。先用临时环境实测登录、会话恢复、双人越权、退出和两人共享消息，再申请线上接入。 [Open WebUI API](https://docs.openwebui.com/reference/api-endpoints/) · [0.13.3 登录源码](https://github.com/open-webui/open-webui/blob/v0.13.3/backend/open_webui/routers/auths.py) · [0.13.3 频道源码](https://github.com/open-webui/open-webui/blob/v0.13.3/backend/open_webui/routers/channels.py)

## 验证与截图

浏览器检测方法见 [启动和测试说明](../frontend/README.md)。使用本机 Playwright 1.65.2 与 Chrome 157 触控模拟，分别跑 360×800 和 390×844。

| 场景 | 实际结果 |
|---|---|
| 环形首页 | 两种尺寸各四个节点，无横向溢出，首页无需纵向滚动。周末需求改变首页关联功能。 |
| 功能及小宇宙 | 两种尺寸逐一打开全部十二项、展开详情、进入编辑再返回，小宇宙为独立路由。 |
| 导演与确认 | 输入带预算的周末需求，生成四张可点击草稿。验证确认预览、键盘关闭并继续编辑、取消后原内容保留、确认保存、刷新恢复和个人／共同版本切换。 |
| A/B 档案与聊天 | 两种尺寸均验证对方档案可读、对方的编辑路由不可编辑、另一位演示账号无法打开原个人草稿、公开偏好确认前后可见性、共同空间 `@AI` 结果，以及已确认偏好影响后续模拟约会。 |
| 安全与稳定性 | 无页面或控制台错误，无第三方请求。输入的 HTML 片段以纯文本渲染，无法创建元素。 |

截图使用合成数据保存于 [frontend/evidence](../frontend/evidence/)。[360×800 首页](../frontend/evidence/home-360.png) · [390×844 首页](../frontend/evidence/home-390.png) · [功能目录](../frontend/evidence/modules-390.png) · [导演草稿](../frontend/evidence/director-390.png) · [确认](../frontend/evidence/confirmation-390.png) · [档案](../frontend/evidence/profiles-390.png) · [独立小宇宙](../frontend/evidence/universe-390.png)

## 当前边界

本版完成前端本机体验。真实账号接入、真实 AI、云端记忆与同步、Mini-IPIP 测评、手机实机测试、外部预览和 PWA 尚待后续。开发期间未修改 ECS、Docker、数据库、Funnel、DNS、防火墙与现有站点配置。原有公网入口仍由 Open WebUI 提供。用户体验验收待进行。
