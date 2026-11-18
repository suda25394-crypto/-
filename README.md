# 情侣 AI 生态｜AI 主导的情侣超级 App（产品名待定）

Android 私人 Demo **0.4.0+4** 的[测试 APK 及校验值](https://github.com/suda25394-crypto/-/releases/tag/android-dp-v0.4.0-test.4-r2)、[按 D 编号的验收结果](planning/ANDROID_0_4_RECEIPT.md)和 [Muse 部署交接](deploy/couple/MUSE_0_4.md)在此开发分支。

规划与 Android 开发进度见[双边交接页](planning/ANDROID_PLANNING_HANDOFF.md)，其中列出了已验收功能、可安装测试包、Muse 基线和后续任务。

> **项目本体：AI 主导的情侣超级 App。**  
> **“双生宇宙”只是 V0.1 小宇宙演示原型的临时名字，不是整体产品已经确定的名称或全部方向。**  
> 仓库：`suda25394-crypto/-`｜私有项目资料中心｜最后校正：2026-11-17

## 一句话定位

**AI 先了解两个人，再根据当下需求、双方授权的关系记忆和使用情境，动态选择、编排、联动不同情侣功能，形成会随着两个人生活持续变化的产品体验。**

不是：情侣工具箱 + AI 聊天窗口。  
也不是：一个小宇宙游戏 + 几个附属功能。  
而是：**AI 智能中枢 + 丰富且互联的情侣功能生态**。

## 长期粘性的核心机制（2026-11-16 新确认）

**像用户所说的 Muse 式体验：越用越懂你，越用越觉得好用。** 首次惊艳只是获客入口；真正的留存来自随时间累积、可纠正、经双方授权的关系理解，并让每次推荐和联动比上次更贴合需求。

**这不是“让模型自己训练权重”**，而是“关系记忆 + 当前情境 + 反馈纠错 + 动态模块编排”的闭环。AI 不应只是首次问卷贴标签，也不是不停弹出同一套推荐。

## 正确的产品层次（必须优先理解）

```text
情侣双方：需求、偏好、共同经历、实时反馈
            ↓（自愿分享与权限控制）
       AI 智能中枢 / 调度系统
     ├─ 关系记忆：理解与维护可授权的关系背景
     ├─ 功能导演：识别意图，动态选择/组合功能
     ├─ 秘密策划师：创造个性化惊喜与日常互动
     └─ 关系守护者：促进沟通，争执前后提供支持
            ↓
      可独立存在、彼此联动的模块
  约会计划｜心愿清单｜相册回忆｜沟通｜共同生活
  惊喜礼物｜活动游戏｜AI 故事｜专属小宇宙
  更多未来可接入的模块……
```

> 上述四个 AI 角色是用户明确喜欢并要求保留的**功能架构方向**，不是四个已经实现的模型或必须分别运行的 Agent。一个低成本模型加业务逻辑就可能承担多个角色。

**小宇宙的位置：**优秀的视觉化、故事化核心功能之一，可作为首次惊艳体验候选，但不得成为其余功能唯一的入口、目的地或中心数据模型。

## 从这里读起

| 分类 | 文件 | 用途 |
|---|---|---|
| 总体定位 | [docs/PROJECT.md](docs/PROJECT.md) | 用户目标、AI 中心与产品边界 |
| AI 核心架构 | [docs/AI_CORE.md](docs/AI_CORE.md) | 四种 AI 能力、动态决策与模块联动 |
| **确认决策** | [docs/DECISIONS.md](docs/DECISIONS.md) | 事实级产品约束，开发必读 |
| 功能模块 | [docs/FEATURES.md](docs/FEATURES.md) | 丰富功能的分层及状态 |
| 首次体验 | [docs/EXPERIENCE.md](docs/EXPERIENCE.md) | AI 主导引导与黄金开局 |
| 技术构想 | [docs/TECH.md](docs/TECH.md) | 低成本、可约束的 AI 调度方式 |
| 商业化 | [docs/BUSINESS.md](docs/BUSINESS.md) | 免费/会员与成本假设 |
| 竞品调查 | [research/COMPETITORS.md](research/COMPETITORS.md) | 海内外产品参考，仍需逐项核验 |
| 创意储备 | [ideas/BACKLOG.md](ideas/BACKLOG.md) | 未确立需求与未来功能 |
| **与 DP 聊出个人档案** | [对话建档规范](docs/PROFILE_QUESTIONNAIRE_FINAL_V1.md) | 本人自由表达与确认，已发布档案双方互看；附历史量表依据 |
| **进度** | [planning/PROGRESS.md](planning/PROGRESS.md) | 已部署底座、真实验收状态、未实现能力与下一步 |
| **服务器交接** | [planning/SERVER_HANDOVER_2026-11-16.md](planning/SERVER_HANDOVER_2026-11-16.md) | Open WebUI 与网关已部署；DeepSeek 未启用；Tailscale 私网入口已配置 |
| **公网访问实施记录** | [planning/PUBLIC_ACCESS_FUNNEL_2026-11-17.md](planning/PUBLIC_ACCESS_FUNNEL_2026-11-17.md) | Tailscale Funnel 已开通，站外 HTTP 200；真实账号登录与双手机验收待完成 |
| **手机 PWA 实施方案** | [planning/MOBILE_PWA_PLAN.md](planning/MOBILE_PWA_PLAN.md) | 复用 Open WebUI 原生 PWA；本地验证完成，公网 HTTPS 与真机安装待验收 |
| 协作约定 | [planning/WORKFLOW.md](planning/WORKFLOW.md) | GPT 总控、Codex 开发、Muse 运维，以及重要变化主动同步规则 |
| 演变记录 | [history/DISCUSSION.md](history/DISCUSSION.md) | 初始需求至本次纠偏 |
| **对话方向审计** | [history/DIRECTION_AUDIT_2026-11-16.md](history/DIRECTION_AUDIT_2026-11-16.md) | 逐轮核对真实意图、识别范围漂移与留存机制 |
| **历史原型 V0.1** | [prototype/v0.1/](prototype/v0.1/) | “双生宇宙”单页局部演示，历史资料保留 |
| **交互原型 V0.2** | [prototype/v0.2/index.html](prototype/v0.2/index.html) · [说明](prototype/v0.2/README.md) | 历史 AI 首页草稿，用户反馈信息密集，未通过设计验收 |
| **交互原型 V0.3** | [prototype/v0.3/index.html](prototype/v0.3/index.html) · [说明](prototype/v0.3/README.md) | 统一 AI 对话、展示卡片的上一版，用户指出仍有冗余 |
| **手机抽卡 V0.4** | [prototype/v0.4/index.html](prototype/v0.4/index.html) · [说明](prototype/v0.4/README.md) | 五套手机端 UI 抽卡评选，用户可收藏方案，待用户体验 |
| **V0.5 抽卡探索** | [prototype/v0.5/index.html](prototype/v0.5/index.html) · [说明](prototype/v0.5/README.md) | 用户仅认可 03 环形中枢，作为下一版选稿基础 |
| **V0.6 环形 AI 中枢** | [prototype/v0.6/index.html](prototype/v0.6/index.html) · [说明](prototype/v0.6/README.md) | 选择 03 方案继续深化：12 个模块、详情、修改与确认、独立小宇宙，待用户验收 |

## 当前发布路径（2026-11-17 用户确认）

**先做手机浏览器可直接使用的 Web 版**，经过功能与体验迭代、相对完善后，再考虑推出正式安装的 App。此决策只确认先后顺序，**不等于 React / Flutter / PWA / Capacitor 等技术栈已定稿**。现有 Open WebUI 公网入口是开发底座；情侣前端 V1 仍在视觉改进阶段，未验收上线。见 [D-39](docs/DECISIONS.md)。

## 当前优先事项

1. **主轴已确认**：AI 动态调度多个情侣功能，而非单一宇宙。
2. **服务器底座已部署**：Open WebUI 与 DeepSeek Gateway 已运行，Tailscale 私网入口已配置；真实 DeepSeek 尚未启用，两部手机尚待验收。
3. **[公网入口已开通](planning/PUBLIC_ACCESS_FUNNEL_2026-11-17.md)**：免费 Tailscale Funnel 可供未安装 Tailscale 的手机访问；原私网入口仍正常。
4. **本地情侣前端 V1 已交付**：[运行说明](frontend/README.md) · [实施记录](planning/FRONTEND_V1_IMPLEMENTATION_2026-11-17.md)，位于 `codex/couple-frontend-v1` 分支，尚未合并 main。
5. **视觉验收未通过**：用户认为当前图形平庸、不够惊艳；详见[视觉评审](planning/FRONTEND_V1_DESIGN_REVIEW_2026-11-17.md)。本地交互可运行不等于 UI 验收通过。
6. **2026-11-18 最新客户端任务（D-40）**：用户改变当前开发优先级，授权 Codex 使用 **Flutter + Dart 开发 Android 客户端**，自主配置并验证 Windows 本地 Flutter/Android Studio/模拟器环境，要求 IDE 左侧可见代码、右侧 Android 模拟器运行，支持 Hot Reload。旧 Web 项目与现有服务器保留。3 套视觉方向仍是设计建议，尚非已批准定稿。

状态标记：✅ 用户确认的方向｜🧪 已有可检查的演示文件｜💡 待验证的设计｜⏳ 尚未实现。不要把创意、源码、上线和验收混淆。

## 当前施工任务（2026-11-18，D-41）

[Android 私人 Demo 功能交付](planning/ANDROID_FUNCTIONAL_DEMO.md)｜本机已有可运行客户端与调试 APK，当前由 Codex 接通真实模型、账号、云端业务与双人同步。视觉与用户并行讨论，用户选稿后另行实施。详见[最新进度](planning/PROGRESS.md)。

### Android 私人测试版

Muse 交接分支的安装版本为 0.2.0+2。可使用离线演示入口体验，也可在 Muse 配置产品服务后通过原有账号登录。代码、测试、APK 签名与真机验收状态见[功能交付回执](planning/ANDROID_FUNCTIONAL_RECEIPT.md)，部署材料见[Muse 交接](deploy/couple/MUSE.md)。


本分支 Android 测试版为 **0.3.0+3**。模块详情支持私人或共同续聊、编辑并确认原记录。另提供活动意愿、情境委托、实际反馈和共同回忆小游戏。新版服务可在本机独立运行。[安装、体验路径与双账号验收](planning/ANDROID_DP_D42_D43_RECEIPT.md)
