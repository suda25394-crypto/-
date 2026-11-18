# 两个人 · Flutter Android 私人 Demo

项目使用 Flutter 3.50.0、Dart 3.14.0。Windows 工作台使用 JDK 21 与 Android API 36。手机端的正式入口是 `lib/main.dart`。

## 登录与演示

首次打开时选择一种方式。

- **登录私人空间**。输入 Muse 提供的 HTTPS 产品服务地址，以及已有 Open WebUI 普通账号的邮箱和密码。地址指向情侣产品 API 的前缀，例如同源部署使用 `https://主机名/couple`，由客户端追加 `/v1/…`。也可在构建时用 `--dart-define=COUPLE_SERVICE_URL=…` 填入默认服务地址。两人的账号与既有共同频道由服务端核对。手机仅保存产品会话，并通过 Android 加密存储恢复登录。
- **体验本机演示**。此入口使用合成 A/B、内存数据和本地规则。右上角「退出本机演示」返回登录页。
- **合成联调**。连接测试 fixture 后，账号菜单显示「合成联调」，模型回复带有合成标识。fixture 提供真实 HTTP 与 SQLite 读写，并使用测试身份和合成模型。

## 一次双人体验

1. A 从首页进入「和 AI 聊聊」，输入「我不喜欢人多」。打开「草稿与记忆」，核对候选内容并选择仅自己保存、发布或拒绝。
2. B 在「共同」发送「@AI 周六想出去，预算 200 元」。打开共同草稿修改时间，确认写入后双方在「功能」中查看记录。约会、心愿、共同日程、共同记忆也支持手动创建与修改。
3. A 可在记忆页纠正或撤回共享。进入「档案」查看、填写及确认发布自己的资料。右上角账号按钮支持退出。
4. 账号页、聊天和模块均以获准的云端数据为准。前台每四秒刷新，也会在保存和切回应用时更新。网络错误会提示重试，失败消息可从「我的待处理消息」取回原提交编号。结果不确定的模型调用需要使用者明确确认后才能重新请求。

## 本机运行

Windows 可以双击仓库根目录的 [Android开发工作台.cmd](../../Android开发工作台.cmd)。预览由 Android Emulator 提供，VS Code 打开同一工作区的 Dart 文件。启动器检测现有调试进程，保存 `lib/` 下的 Dart 源码会触发 Hot Reload。

也可以从工程目录手动执行。

```powershell
Set-Location D:\dev\couple-ai-flutter\apps\android
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d emulator-5554
```

## 本机 HTTP 联调

在仓库根目录启动仅监听回环地址的测试服务。

```powershell
python -m services.couple.tests.fixture --port 18787
```

在另一窗口把模拟器接到该服务，再回到应用登录页输入 `http://127.0.0.1:18787`。测试邮箱为 `a@example.test` 和 `b@example.test`，合成口令为 `fixture-only`。

```powershell
adb -s emulator-5554 reverse tcp:18787 tcp:18787
```

日常测试可使用以下命令。其中网络验收用例须连接正在运行的本机 fixture；常规 `flutter test` 会跳过这一项。每次完整验收应使用新的临时 fixture 数据目录。

```powershell
flutter test --dart-define=COUPLE_FIXTURE_URL=http://127.0.0.1:18787
flutter build apk --debug
```

测试包默认生成在 `build/app/outputs/flutter-apk/app-debug.apk`。Debug 构建允许本机回环 HTTP 联调。两台真机通过 Muse 配置的 HTTPS 产品服务连接，模型密钥由服务端管理。部署和运维请参阅 [Muse 交付说明](../../deploy/couple/MUSE.md)。
