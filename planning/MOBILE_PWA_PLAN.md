# 情侣 AI Demo｜手机 PWA 实现方案

2026-11-17 · 基线 `fa6c1cf`，Open WebUI `v0.13.3-slim`（镜像摘要以 Compose 为准）。本轮完成方案和本机验证。发布仍需经确认的公网 HTTPS 地址和双手机验收。

## 决定

首版直接安装 Open WebUI PWA。桌面图标打开同一个站点，由现有 Open WebUI 登录、私聊和共同频道承接交互。选择一个稳定、两部手机都可从普通网络访问的 HTTPS 域名，登录仍限指定账号。PWA 安装后继续访问原站点，Tailscale Serve 的 tailnet 地址不能满足免 Tailscale 访问。 [Open WebUI PWA](https://docs.openwebui.com/getting-started/open-webui-as-app/) · [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)

## 安装与品牌配置

| 项目 | 固定版本核对结果与首版做法 |
|---|---|
| 安装 | HTML 已链接 `/manifest.json`。原生 manifest 的 `start_url` 为 `/`、`display` 为 `standalone`；Android 和 iPhone 均走浏览器自己的安装入口。 |
| 安装名称与图标 | 自定义 manifest 填 `name`、`short_name`、稳定的 `id: "/"`、`start_url: "/"`、`scope: "/"` 和 `display: "standalone"`，避免在启动 URL 放账号、令牌或特定频道 ID。准备 192×192、512×512 PNG 和独立的 maskable 图标。名称与图案在两人试用前确定。单设 `WEBUI_NAME` 会给页面名称加 ` (Open WebUI)` 后缀。 |
| iPhone 桌面图标 | 固定版本的 HTML 独立引用 `/static/apple-touch-icon.png`。Safari 可优先使用这个 180×180 图标，单换 manifest 不会更改该资源。交付自定义图标时同时替换这一地址的内容，并核对安装确认页的标题。 |
| 启动画面 | Android 可由浏览器按 manifest 图标、`background_color` 等生成启动画面。Open WebUI 页面加载屏分别引用 `/static/splash.png` 和 `/static/splash-dark.png`，可用独立资源替换。固定版本未声明 iOS 的 `apple-touch-startup-image`；首版使用系统启动过渡，若后续确有必要，再以目标 iPhone 验证自定义系统级启动图。 |
| 接入方式 | 上游支持 `EXTERNAL_PWA_MANIFEST_URL`，由服务端取 JSON 再经自身的 `/manifest.json` 返回。若已有获准的公网反代，建议它从同源直接交付自定义 manifest 和图标，以减少每次获取 manifest 对另一服务的依赖。使用上游变量时指向可信静态资源地址，避免指向自己的 `/manifest.json`。独立覆盖品牌静态路径或从构建输入更新资源；上游启动会从构建目录重新复制静态资源。 |
| 许可 | 锁定版本许可对任意滚动 30 天内最多 50 名终端用户的部署有品牌调整例外。本 Demo 的两人范围符合数量条件。保留上游版权和许可文件，扩大受众前重新核对。 |

[Open WebUI 固定版本源码](https://github.com/open-webui/open-webui/tree/v0.13.3) · [固定版本许可](https://github.com/open-webui/open-webui/blob/v0.13.3/LICENSE) · [Manifest 配置](https://web.dev/learn/pwa/web-app-manifest) · [WebKit 图标优先级](https://webkit.org/blog/12445/new-webkit-features-in-safari-15-4/) · [Apple 启动图说明](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/ConfiguringWebApplications/ConfiguringWebApplications.html)

## 两部手机怎么用

- **Android Chrome**：第一次打开公网 HTTPS 链接，菜单 →「添加到主屏幕」→「安装应用」。若只看到「创建快捷方式」，检查 manifest 和浏览器安装条件；首版验收要求点图标进入独立窗口。 [Chrome 安装文档](https://developer.chrome.com/blog/how_chrome_helps_users_install_the_apps_they_value)
- **iPhone Safari**：第一次打开同一链接，分享 →「添加到主屏幕」。系统若显示「作为网页 App 打开」，保持开启，再点添加。安装后直接点图标，从应用窗口用各自账号登录，复测关闭重开和登录过期流程。 [Apple 安装文档](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/27/ios/27)
- 两部手机首次接收链接时各操作一次。日常从桌面直达。当前本地实测无注册的 Service Worker，聊天仍依赖联网，首版不缓存聊天和档案作离线使用。

## 界面与轻量前端

手机原生界面足够承接**首轮体验**。在 360×800 和 390×844 下，私聊输入框、共同频道消息和输入框均能显示，无横向溢出。两套触控会话成功点选 `@AI`，伙伴无需刷新就能收到群聊消息并点开同一离线夹具回复。

截图也显示三个体验差距：私聊首页仍显示学习、期权等通用建议；共同频道入口在侧栏；AI 结果默认需要点开消息下方的回复线程。首版先设置单一 AI 模型，使用 `DEFAULT_PROMPT_SUGGESTIONS` 提供少量和两人生活有关的提示，安装后引导打开「我们和 AI」。这些是方案项，已核对配置入口，尚未写入运行配置。暂不开发额外前端；真机测试若发现共同入口仍难找，或双方档案与日程需要直达，再评估一屏轻量入口并复用同源登录状态和现有聊天。 [原生频道](https://docs.openwebui.com/features/channels/) · [环境变量](https://docs.openwebui.com/reference/env-configuration/)

## 实施顺序与发布条件

1. **离线品牌打包**。确认应用名和图标后，准备 manifest、普通与 maskable 图标、iOS 图标和浅深色加载资源。将来若用既有反代提供同源资源，只覆盖明确的静态路径，其余登录、私聊、频道、WebSocket 和流式响应交给原服务。本版前端更新时会注销同源 Service Worker，因此推荐独立子域。
2. **授权后接入公网 HTTPS**。沿用现有 ECS 上的回环绑定，公网由获准的反向代理终止 TLS。将 `DEMO_WEBUI_ORIGIN` 对齐 HTTPS 域名，保留安全 Cookie、关闭注册，确认只有两位普通账号、群成员访问权限正确、登录与私聊接口无缓存。使用现有域名和网关时先核查冲突、备案与云接入条件；北京节点公开站点按阿里云备案要求确认。无已批准入口时等待决定，保留现有网络配置。 [阿里云备案说明](https://help.aliyun.com/zh/icp-filing/basic-icp-service/product-overview/what-is-an-icp-filing) · [反代 WebSocket 能力](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
3. **用移动网络验收**。两部手机关闭 Tailscale，至少用移动数据测试一次 HTTPS 地址及证书。分别安装，记录 OS、浏览器和应用名称、图标、启动与安全区；从桌面杀掉重开、再次登录、切换私聊与共同频道。两人用合成数据验证私聊互不可读、群消息与 `@AI` 线程都可见、匿名无权限、安全 Cookie 和 WebSocket 正常。真实模型验收单独使用已有授权与限额。
4. **回滚**。品牌资产和将来的代理入口可独立撤回，保留现有数据卷。已有桌面安装的图标可能缓存；用真实手机验证更新，必要时移除旧图标并按确认后的正式域名重新添加。现有 ECS 状态见进度账本。

## 本轮实际验证

| 项目 | 结果 |
|---|---|
| 默认 manifest | 临时 Windows 原生 Open WebUI 0.13.3 进程使用同版本 Slim 依赖；从 `/manifest.json` 获得默认名称和 `standalone`，实际图标 500×500。Chrome 157 独立持久化测试配置在回环安全上下文的 CDP `Page.getInstallabilityErrors` 返回空，仅有非关键的 `share_target.enctype` 提示。 |
| 自定义 manifest | 在第二个临时实例中将 `EXTERNAL_PWA_MANIFEST_URL` 指向本机静态夹具，HTTP 实测独立名称、192/512 PNG 与 `scope=/`，Chrome 未报告 manifest 解析或安装条件错误。`WEBUI_NAME` 仍有品牌后缀；iOS 图标链接确实保持原路径。 |
| 移动界面 | Playwright 1.65.2 + Chrome 157.0.8103.79，触控 390×844。复跑仓库的 [端到端脚本](../demo/tests/verify_webui.py)，两账号隔离、成员权限、移动端点选 `@AI` 及两人看回复通过。追加中文界面截图核查，360×800、390×844 的私聊和频道横向溢出均为 0 px。 |
| 测试边界 | 在本机回环地址用合成账号和离线模型夹具。没有在 Android/iOS 实装测试，没有验证公网可达性或真实回复；无真实 DeepSeek 调用，没有变更 ECS 网络、DNS 或代理。 |

复查方法：启动一次性的原生 WebUI，用 `GET /manifest.json` 和 PNG 请求核对品牌字段；在独立 Chrome 配置的 DevTools Application → Manifest 检查。以已有端到端脚本测试移动群聊；打开私聊和共同频道，记录两种视口的截图及 `document.documentElement.scrollWidth - innerWidth`。本机临时证据位于 `%TEMP%/couple-demo-upstream-v0133/smoke-89fd16a61a/` 和 `smoke-e791ebe2af/`，包含合成账号界面截图和测试服务日志。 [Chrome PWA 调试](https://developer.chrome.com/docs/devtools/progressive-web-apps/)


## 2026-11-17｜公网 HTTPS 入口已开通

- Muse 已开通 Tailscale Funnel，现有 HTTPS 地址为 `https://iz2zecx08mwosw8t20kovoz.tail13b871.ts.net/`；站外 HTTP 200、首页与健康检查正常，原私网入口仍正常。实施证据见 [Funnel 实施记录](PUBLIC_ACCESS_FUNNEL_2026-11-17.md)。
- 因此本方案原先的“等待公网 HTTPS 地址”条件已满足，可以进入真实账号和手机验收。
- **尚未完成**：Demo A / Demo B 真实密码登录、Android/iPhone 真机添加到主屏幕、冷启动、移动数据访问，以及双手机私聊/共同频道复测。
- 当前验收顺序：双方分别用自己的账号从普通网络打开上述地址并登录；通过后再按本文件前文安装 PWA。不要把账号密码发到聊天或写入仓库。
