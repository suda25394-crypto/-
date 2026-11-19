# 双生宇宙 · 改期原型

独立 Android 包 `com.coupleai.dshdate`，与现版 `com.coupleai.couple_app` 可以同时安装。原型首次打开需自行登录。使用原有配对账号及现版填写的 HTTPS 产品服务地址，两端共用原来的 R2 数据。未对线上服务做部署或迁移。

## 打开和试用

1. 两人各自登录并打开同一条已有日期和时间的共同约会。空账号可先在现版建一条有时间的共同计划。
2. 你在这条约会里选「私下问 DP」，发送「把约会推迟半小时」。页面展示旧日期时间和建议的新日期时间。
3. 核对后点「确认改期」。伴侣保持打开这条约会即可看见新时间。私人对话只在自己名下出现。取消提议会保留原时间。
4. 原型在前台自动检查日程变更。两人强停重开同一日程、或在现版进入同一条计划，可以核对日期、时间、地点和记录身份。

## 原理和来源

源自 [dsh-Go v1.2.0](https://github.com/ccch1mneyyy/dsh-Go/tree/c1a84e3f833ad59ff07a5027994dae3935907a2d) 的独立 Flutter 客户端发行目标。本目录含构建 APK 所需的对应源码。直接沿用上游的 `packages/dsh_client` 中的 `ChatTranscript` 对话事件处理、Flutter `ChatCard`、`ChatCardFooter`、主题和图标字体。2026-11-19 新增双账号业务适配、日程页、对话页和独立 Android 宿主；`chat_card.dart` 的主题导入缩小到卡片依赖。此原型走双生宇宙 R2 的 DP 对话接口，手机上无需安装 Linux 运行时或填写模型密钥。应用内包含独立发布页和源码链接。

DP 对话以当前账号、日程 ID、私有/共同范围和记录版本为上下文。对明确的「推迟半小时」在本机用原日期和时刻准确加 30 分钟，包含跨日。DP 回复由账号配置的服务返回。仅当收到本次请求的 DP 回执时才出现确认卡。对话使用只生成说明的请求，避免产生额外可执行的文本草稿。确认时以原日程 ID、版本和可重试的操作号调用原 R2 的结构化排期接口；旧记录内容及集合地点保留。确认时如连接断开且尚未收到响应头，原型会另开一次连接，以相同操作号重试。即使首个请求已经写入，服务也只应用一次。遇到对方先改期，会要求重新核对新版本。该流程用于原型支持的 30 分钟顺延，真实账号调用 DP 按原有额度计。

接收端前台约每 800 ms 检查 R2 已有的 `/v1/life/changes`，收到新变化才读取最新完整日程，另有低频校准；进入后台停查。此版本验证的是共同日程的可见变更。使用原产品的 HTTPS 登录，并将会话存于系统安全存储。不含生产地址、模型密钥、签名私钥或真实账号数据。

## 构建与复测

源码包解压后从本目录运行（Flutter SDK 含 Dart 3.14、Android SDK 36、JDK 21）。标准 Flutter 构建会根据本机 Android SDK 生成 `android/local.properties`。

```sh
flutter pub get
flutter test
flutter build apk --release --target-platform android-arm,android-arm64,android-x64
```

要运行两账号网络回归，先在本仓库已有 R2 服务的 Python 环境启动 `python -m services.couple.tests.fixture --port 28214`，再在本目录运行 `flutter test --dart-define=COUPLE_PROTO_TEST_PORT=28214`。该测试要求全新的合成数据库。应用默认 Release 签名配置适用于这个原型包。自行构建使用构建者自己的密钥。

分发遵循 [AGPL-3.0](LICENSE) 及各文件头附带的许可，第三方来源和字体见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。上游品牌和吉祥物说明见 [ASSETS.md](ASSETS.md)。本版用双生宇宙自己的名称、图标和界面文案。
