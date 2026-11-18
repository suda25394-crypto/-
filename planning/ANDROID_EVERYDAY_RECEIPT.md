# 双生宇宙 Android 0.5.0+6 双人试用

[下载可覆盖安装的 APK](https://github.com/suda25394-crypto/-/releases/download/android-everyday-v0.5.0-test.6/couple-everyday-0.5.0-test.6.apk) · [SHA-256](https://github.com/suda25394-crypto/-/releases/download/android-everyday-v0.5.0-test.6/SHA256SUMS.txt) · [本版源码](https://github.com/suda25394-crypto/-/tree/c66e7d57a7611b479cd5ad6946087b7d98074185)

两部手机都选「更新」，打开后使用原有配对账号。两个玩法都在底部「功能 → 两人互动」里。

| 实际新增 | 你先做什么 | 对方能接着做什么 |
|---|---|---|
| 双人便签 | 点「双人便签 → 写一张便签」，留一句话，点「贴给伴侣」。 | 打开同一页，点「收下并回信」。你们重开后能在原便签上看到收下状态和回信，对方也能修改回信。 |
| 约会行动签 | 点「约会行动签 → 抽一张行动签」，选出门、宅家或异地，揭晓后点「邀请伴侣」，你也选一个态度。 | 对方可以选「愿意」「再想想」或「这次不约」。双方愿意后，从「打开共同心愿，安排日期」填时间和集合点。两人再开原签就能直达日程。心愿详情还可「私下问 DP」或「两人共同续聊」。 |

抽签、贴便签、回信、表态与排期复用现有 R2。两个独立测试账号在 Android 13 模拟器的不同系统用户下操作。上游使用合成服务，普通玩法没有调用模型。测试中发现排期会推进心愿的版本，原签曾显示双方又要投票。最终版按心愿 ID 找到关联的日程或回忆，直接显示已保存的安排；退回心愿后才重新表态。[动作卡实现](../apps/android/lib/src/ui/pair_activities.dart) · [状态转换测试](../services/couple/tests/test_pair_activities_r2.py)

从 GitHub 公开下载地址匿名取回 APK，复核完整摘要、v2 签名和安装清单。在同一台模拟器上先用旧公开包分别打开 Alice 和 Bob 的原账号，再直接覆盖安装回下载的新版。两人均无需重新登录；各自强停重开仍见原便签和回信、「交换小菜单」双方愿意，以及「同步听歌」的 14:30 集合安排。另在最终构建中实际从零新建便签并回信，抽新签、分别表态后两人再次重开看见相同结果。[重新打开的回信](evidence/android-everyday-0.5.0/note-reply-reopened.png) · [两人都愿意](evidence/android-everyday-0.5.0/both-agreed.png) · [排期后重开原签](evidence/android-everyday-0.5.0/scheduled-card-reopened.png)

## 聊天究竟慢在哪

**这次改善最明显的是自己的消息上屏。剩下影响双人聊天最多的是对方等待下一轮同步。** 普通发送现在先绘制待确认气泡，失败可用原请求号重试。翻看旧消息时，有新消息也保持阅读位置。轮询收到相同状态时跳过整页通知，测试中 15、120、1000 条历史的相同快照各从 19 次被跟踪的组件构建降到 0 次。R2 在前台仍每 4 秒拉取状态一次。[发送与列表](../apps/android/lib/src/ui/cloud_chat.dart) · [状态同步](../apps/android/lib/src/services/cloud_session.dart) · [弱网与并发回归](../apps/android/test/chat_delivery_test.dart)

**两个已复现的阅读位置问题。** A 翻到群聊中部，B 发一条消息，旧版 A 正读的气泡移动约 79 dp；同一组件场景复测为 0 dp。A 自己停在旧记录时发送，旧版仍与最新位置相距 1620 dp，新版回到最新位置显示自己的消息。最初反馈的具体 bug 尚无操作步骤，无法确认是否与这两项相同。[旧版复现过程](../research/ANDROID_CHAT_DIAGNOSIS_2026-11-19.md)

| 同条件实测 | 旧版 → 新版 | 怎么读 |
|---|---|---|
| 点击发送 → 自己的气泡 | **960 → 266 ms**，中位数 | Debug 对 Debug，各发 4 条。用 Flutter 语义树辨认只读消息节点，排除输入框。 |
| 自己的气泡 → 对方客户端收到 | **1.88 → 2.58 秒**，中位数 | 与上一行是同一批发送。自己的气泡提早出现，对方仍在轮询周期到来时收到。按 Release 另测点击发送到对方收到为 **2.89 → 2.89 秒**。接收时刻取第二账户 R2 客户端读到消息。 |
| 冷启动进群可输入／弹出键盘／切到私聊 | **2.02 → 1.95 秒**／**0.94 → 0.97 秒**／**0.22 → 0.30 秒** | Release 对 Release，每项 3 次的中位数。 |
| 点发 @DP → 模型开始处理／完整回执出现在聊天里 | **321、360 → 342、343 ms**／**1.31、1.34 → 1.45、1.31 秒** | 各 2 次；上游固定等待 650 ms。当前回复接口整条返回，未测真实 DeepSeek 首字。 |
| 上下翻历史 | 呈现间隔中位 **16.81 → 17.15 ms**；P95 **26.69 → 32.92 ms** | 最终安装包与旧版 AOT 各 6 次；每次手指实际拖过 909 px，取仍按住的 800 ms。新版这一轮长尾更高，滚动流畅度仍待真机 Profile 定位。 |

比较使用同一台 Android 13 模拟器，40 条初始群消息、相同配对账户，发送与读状态各注入 150 ms 延迟。对方收到以四个不同轮询相位采样，包含接收端等待；自己的气泡时间含观测开销。公开旧包是 Flutter Debug，Release 对照用同一旧源码 ff47348 重建。同模式聊天复测的候选为 b87471e，最终源码 c66e7d5 的客户端变化限于行动签；固定拖动用最终发布件源码复测。键盘、切私聊与滚动均未确认提速。下一轮优先分别追踪真机慢帧与 R2 消息增量同步。[逐次数据](evidence/android-everyday-0.5.0/chat-measurements.json) · [逐帧拖动结果](evidence/android-everyday-0.5.0/scroll-contact.json) · [旧版诊断](../research/ANDROID_CHAT_DIAGNOSIS_2026-11-19.md)

## 参考产品与验收范围

Twoo Android 0.6.0（60010）为 React Native／Expo 客户端，包名 `com.beingbeing.twoo.android`，本地 APK 的 ZIP 完整性和 v2 签名通过。实机操作范围为模拟器上的协议、隐私页和退出。没有可用的登录账号，便签、抽取、小屋和提醒的登录后流程依据该版本的路由、业务代码及官方资料。双生宇宙沿用 Flutter，实现原创九张行动签与伴侣回信，使用既有共同日程和记录。参考 APK、代码及素材保存在仓库外。[逐项产品对照](../research/TWOO_PRODUCT_WALKTHROUGH.md)

应用 ID 为 `com.coupleai.couple_app`，三架构 AOT Release，55,135,602 字节。APK SHA-256 为 `234b350ae312ccc00d976c529ecb47d33592c7dd42d8f114a8e1d1b6f89a6ece`。签名证书 SHA-256 为 `5fb24bed41d8b34fe1a7cb5ed5dd98b2438791873bdaa36e291707a3c43105df`，与公开旧包相同。Flutter 47 项、R2 服务 60 项通过，Android Release 关键 lint 通过。测试覆盖 503 恢复、409 幂等重试、群私聊隔离和强停重开。公网 R2、真实模型时延和两台实体手机的滚动手感留待持机试用。
