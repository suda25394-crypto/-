# 情侣私人 Demo 产品服务

正式入口为 `services.couple.api:app`，与部署包配套使用。它通过每位用户自己的 Open WebUI 凭据验证身份和私有频道成员资格。固定配对由两个普通用户 ID 和一个频道 ID 决定；更换账号或频道会建立隔离的数据范围。

手机使用服务签发的七天期令牌。SQLite 保存令牌摘要和加密后的上游会话。两部设备分别登录，依各自的授权读取 `GET /v1/state`。退出会撤销当前产品会话。部署须使用单个 Uvicorn worker，以便授权变更与共享回复投递按同一顺序执行。正式部署使用独立密钥、私有网络和 HTTPS，见仓库的 `deploy/couple`。

## HTTP 接口

除登录和健康检查外，需要 `Authorization: Bearer <产品会话>`。接口返回 JSON，错误结构为 `{"error":{"code":"…","message":"…"}}`。

| 路径 | 用途 |
| --- | --- |
| `POST /v1/login`、`POST /v1/logout` | 用已有账号登录，撤销本次会话 |
| `GET /v1/health` | 查看产品服务和数据库是否可用 |
| `GET /v1/state` | 当前用户可见的档案、记忆、草稿、共同模块、消息和待处理提交 |
| `POST /v1/messages` | 发送私聊或共同消息。共同消息中使用 `@AI` 触发模型 |
| `PUT /v1/profile` | 保存自己的私有草稿，或确认发布。发布副本只包含双方获准查看的字段 |
| `POST /v1/profile/withdraw`、`DELETE /v1/profile?version=N` | 撤回发布，或删除档案内容 |
| `PUT /v1/memories/{id}`、`DELETE /v1/memories/{id}?version=N` | 本人保存、纠正、撤回共享，或拒绝与删除候选 |
| `POST /v1/drafts/{id}/confirm`、`…/cancel` | 核对、修改、确认或取消模型草稿。确认后的多个模块在同一事务内写入 |
| `POST /v1/modules`、`PUT /v1/modules/{id}` | 用户明确确认后新增共同记录，双方可按版本修改 |

消息使用 `request_id` 幂等提交。同一编号重试之前的提交。版本冲突返回 HTTP 409，用户刷新后核对。渠道投递结果暂时未知时，服务先对账；模型调用可能已产生费用时，重复提交已有编号不会再次调用。模型超时、访问受限、关闭、限额、输出不合格等状态各自保留错误信息。

## 数据边界

- 私聊记录按用户保存在产品数据库。共同消息通过配置的原生 Open WebUI 频道读写，状态接口显示原生频道最近一页。两个普通账号共用产品功能，独立内容按登录身份过滤。
- 量表原始回答和未发布修订仅本人可读。公共投影只包含已发布的资料和完整量表的确定性分数。
- 模型可以提议候选记忆与结构化草稿。只有用户确认才能发布偏好或写入共同模块。服务只接受约会、日程、心愿、回忆四种模块类型。
- 模型上下文按场景筛选。用户撤回授权会更新上下文版本；遇到授权变化时，生成中的旧回复会被丢弃。已主动分享到原生频道的消息保留该频道的历史。
- 草稿操作留下按模块分类的确认、修改或取消反馈。私聊草稿的反馈仅用于发起人自己的推荐。用量记录只保留调用状态、日期、请求摘要标识与 token 数。

## 本地验证

在仓库根目录运行。下列测试使用独立临时目录、两个合成账号和可控模型回执。

```powershell
python -m unittest services.couple.tests.test_product services.couple.tests.test_upstream -v
python -m services.couple.tests.fixture --port 18787
```

第二条命令仅监听本机，健康检查和状态返回 `mode=fixture`。测试账号为 `a@example.test` 和 `b@example.test`，测试口令均为 `fixture-only`。这些凭据只由测试入口接受。可用 `adb reverse tcp:18787 tcp:18787` 从连接的 Android 测试设备访问此服务。正式部署的 `mode=live` 指使用真实上游适配器；模型是否启用、是否产生真实用量须通过服务器回执确认。
