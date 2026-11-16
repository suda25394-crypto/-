# 情侣 AI 生态｜AI 主导的情侣超级 App（产品名待定）

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
| **科学题库与个性化画像 V1** | [docs/PROFILE_QUESTIONNAIRE_FINAL_V1.md](docs/PROFILE_QUESTIONNAIRE_FINAL_V1.md) | 已核验中文 Mini-IPIP 20题依据，定稿图文画像、确认更新规则，待开发 |
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

## 当前优先事项

1. **主轴已确认**：AI 动态调度多个情侣功能，而非单一宇宙。
2. **服务器底座已部署**：Open WebUI 与 DeepSeek Gateway 已运行，Tailscale 私网入口已配置；真实 DeepSeek 尚未启用，两部手机尚待验收。
3. **[公网入口已开通](planning/PUBLIC_ACCESS_FUNNEL_2026-11-17.md)**：免费 Tailscale Funnel 可供未安装 Tailscale 的手机访问；原私网入口仍正常。
4. **本地情侣前端 V1 已交付**：[运行说明](frontend/README.md) · [实施记录](planning/FRONTEND_V1_IMPLEMENTATION_2026-11-17.md)，位于 `codex/couple-frontend-v1` 分支，尚未合并 main。
5. **视觉验收未通过**：用户认为当前图形平庸、不够惊艳；详见[视觉评审](planning/FRONTEND_V1_DESIGN_REVIEW_2026-11-17.md)。本地交互可运行不等于 UI 验收通过。
6. **当前下一步建议**：先做 3 个真正不同的手机端视觉方向样本，用户选定后再扩展整套 UI；暂不部署当前视觉版本，也不接真实模型。

状态标记：✅ 用户确认的方向｜🧪 已有可检查的演示文件｜💡 待验证的设计｜⏳ 尚未实现。不要把创意、源码、上线和验收混淆。
