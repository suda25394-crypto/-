# Android 私人 Demo 功能回执 · 2026-11-18

**基线** `main@30d969306037`，按 D-41 接续 D:/dev/couple-ai-flutter 的未提交工程。可安装版本对应本地分支 `codex/flutter-android-v1`，源码提交 `f98d99d154b3`。原 Flutter/Web 页面与素材保留。

## 交付物

- Android 测试 APK `couple-ai-0.2.0-test.apk`，版本 0.2.0+2，com.coupleai.couple_app，168,138,733 字节，SHA-256 `b9c8ae369bd39bd24d1b227792b5601e596062e373d9687c432a273be7d51839`。Android SDK 最低 24，target 36，包含 arm64-v8a、armeabi-v7a、x86_64。apksigner 验证 v2 签名通过，本机测试证书。发行目录为仓库下 `deliverables/f98d99d154b3/`，构建目录及 APK 排除在 Git 外。
- 安装到手机时将 APK 传至设备并从文件管理器打开；也可对已授权连接的设备执行 `adb -s 设备序列号 install -r couple-ai-0.2.0-test.apk`。安装后打开「两个人」。选择「体验本机演示」可直接操作离线页面。生产登录需要 Muse 部署的产品服务 HTTPS 地址。
- Muse 包含业务服务、固定依赖、容器配置、密钥占位说明、初始化、备份恢复工具、健康检查与回滚步骤。入口见 [运维交接](../deploy/couple/MUSE.md) 和 [上游契约](../services/couple/UPSTREAM.md)。生产配对由运维绑定现有两个普通账号及私有频道。

## 实际验收

| 范围 | 环境和结果 |
|---|---|
| 客户端 | Flutter 3.50.0 / Dart 3.14.0。静态分析无问题，使用新回环 fixture 运行 Flutter 用例 14/14 通过，包含两个独立 Dart HTTP 会话以及 360×800、390×844 Widget 交互。 |
| 服务端 | 产品与上游适配 13/13，档案计分、私密投影及备份恢复 4/4。覆盖私下惊喜、未确认偏好、发布与撤回、取消、不重复确认、并发确认、越权隔离、版本冲突、断网/超时/关闭模型/配额、重复发送和重开。 |
| 本机原生上游 | 真实 Open WebUI 0.13.3 后端、既有 Gateway 源码、产品业务服务，在本机独立测试账号/频道中贯通。上游 DeepSeek 提供端使用确定性替身。测试额度设为 4，第 5 次被拒。产品模块和聊天落盘，另起服务读取一致；第三账号被拒。详见上游回执。 |
| Android 安装 | Android 13/API 33 模拟器实际冷启动。镜像中已安装 base.apk 的 SHA-256 与交付文件相同。使用应用登录合成 A；A 在模拟器私聊输入后，独立 HTTP 会话 B 查不到；B 群内发「@AI 周六想出去，预算 200 元」，A 同步看到同一回复及草稿，在界面把时间改为 18:00 并确认，B 读回两条版本 1 记录；强停/重开以及覆盖安装后仍以 A 进入。截图使用合成数据。 |
| ECS 与真实模型 | 本轮没有接触生产密码或 DeepSeek Key；未部署 ECS、没有真实 DeepSeek 调用，实际供应商调用数 0，无线上 token、生产资源实测或收费回执。 |
| 真实终端 | 模拟器 + 独立客户端已验收。两部真实手机的移动网络、重开、数据同步及私密隔离待生产服务部署后，由两位账号主人各自实测。 |
| 运维 | 解析 Compose 配置、校验依赖锁、实测在线 SQLite 备份、完整性校验、向新路径恢复并使旧登录失效。未在本机 Docker 或 ECS 启动交付镜像。 |

[登录页](evidence/android-functional/login.png) · [合成群聊](evidence/android-functional/shared.png) · [交付 APK 重开后的首页](evidence/android-functional/final-installed.png)

## 可操作范围

联机模式支持登录、重开恢复、退出、固定配对、私聊、原生共同频道、群内 @AI、候选记忆拒绝/仅自己保存/发布/撤回/纠正/删除。自己的档案草稿、已发布版本和原始问卷作答独立授权。生活偏好 8 项、相处偏好 6 项可渐进填写；五维问卷按原文题号作答，每组 5 题，满 20 题才发布确定性分数。[题库来源与译文复用边界](ANDROID_PROFILE_SOURCES.md)

约会、共同日程、心愿、共同记忆支持持久化读写，模型输出的跨模块草稿需本人或共同频道获准成员核对确认。其余八个入口仍保留，小宇宙可独立进入场景预览。产品私聊从此客户端开始保存；原生 Open WebUI 的既有私聊历史不自动导入。频道列表以最近 50 条主消息及相应线程窗口同步。撤回记忆会影响后续检索；已主动发给双方的聊天和共同记录各自保留独立历史。

## 复测

在仓库根目录执行：

```powershell
python -m unittest services.couple.tests.test_product services.couple.tests.test_upstream -v
python -m unittest discover -s tests -v
python -m services.couple.tests.fixture --port 18787
```

在另一个终端使用全新的 fixture 数据目录执行手机端验收：

```powershell
Set-Location apps/android
flutter analyze --no-pub
flutter test --no-pub --dart-define=COUPLE_FIXTURE_URL=http://127.0.0.1:18787
```

如果从本机根目录重建相同配置，使用 `powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-test-apk.ps1`。需要 Flutter SDK、Android SDK、JDK 21，ANDROID_HOME 指向 Android SDK。项目已锁定依赖与 Gradle 分发包摘要。Windows 在 pub 缓存和工作区分处 C/D 盘时关闭了 Kotlin 增量编译。本次使用应用模块的 :app:assembleDebug 构建；全工程 assembleDebug 曾因插件的 lint 依赖下载失败。

## 下一次真实验收

Muse 部署本版并验证产品 HTTPS 路径返回健康 JSON，在服务器私下配置已有 Gateway 凭据、两账号 ID 和频道 ID，按批准限额开启 DeepSeek。两人各自在手机中输入自己的账号密码，各自重新打开应用并在移动网络下复跑上面的共享/私密场景。Muse 记录真实模型与实际 token 数、失败恢复及运行资源。公开分发中文 Mini-IPIP 原题另待转载条件明确，当前 APK 通过机构库原题链接支持中文作答。
