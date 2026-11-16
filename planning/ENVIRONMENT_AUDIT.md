# 阶段 0｜环境检查

日期 2026-11-16。基础提交 `eaab3c760ec0e4b92b7eaa03b25720731cd46257`。

| 对象 | 实际检查结果 |
|---|---|
| GitHub | 通过本机 Git Credential Manager 克隆到独立子目录。远端默认和唯一已存在分支为 `main`，初始工作树干净。GitHub 公开接口返回 404。用 `git push --dry-run` 验证了开发分支推送路径。 |
| 仓库内容 | 已完整阅读开工文件；核对 README、PROJECT、DECISIONS、AI_CORE、双人配对资料、问卷定稿、方案 B、FEATURES、PROGRESS、V0.6 视觉/交互与开源底座调研。没有现成运行服务、依赖清单、服务器入口或已完成的模型接入。既有 V0.6 对话使用本地规则。 |
| Windows 开发环境 | Git、SSH 客户端、Node.js、uv、Python 3.12/3.14 已有。`Get-Command` 未找到 Docker、Podman 或 Open WebUI，`wsl --list --verbose` 未列出已安装发行版。 |
| 阿里云北京 | 2 vCPU / 2 GiB 来自项目已知条件。仓库和当前任务没有目标 SSH 主机/登录身份及访问许可，无法进行定向连通性测试。OS/架构、磁盘、Swap、监听端口、防火墙、运行服务、备份、出口均未核验。未访问或变更服务器。 |
| DeepSeek | 本次运行环境未发现 DeepSeek 配置变量（仅查询变量名）；未检查其他项目的秘密文件，未调用模型。 |
| 镜像供应 | `v0.13.3-slim` 是官方固定标签，GHCR 索引返回 amd64/arm64。已比对源码分支的认证、Channel、模型和资源配置；容器启动与 RAM 峰值未测。 |

## 可先执行的工作

1. 在 `demo/` 编写版本锁定的单独部署，监听回环，保留独立数据卷。通过 Open WebUI 创建两个普通账号和一个显式成员的 Group Channel。
2. 把 DeepSeek 密钥限制在模型请求服务里。启用真实调用前验证用量限制和错误路径。涉及真实计费的烟雾测试等用户授权。
3. 接通只读 SSH 后仅检查 `uname -m`、`/etc/os-release`、`free -m`、`swapon --show`、`df -h`、`ss -ltn`、Docker/Compose、现有容器和备份状态。出口探测只检查服务连通性，不发模型生成请求。再依据检查结果确定部署与双手机私网连接方式。

后续双人验证同时使用独立浏览器会话及两部手机；北京节点私网到达性、2 GiB 负载和 DeepSeek 调用结果均需现场取证。官方资料与资源选择见[复用审计](RESOURCE_REUSE_AUDIT.md)。
