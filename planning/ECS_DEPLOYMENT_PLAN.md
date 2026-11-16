# 情侣 AI Demo ECS 审计与部署预案

目标是 `39.97.234.162:22`，备用 SSH 入口是 `100.127.243.70:22`，使用已有 `couple-deploy` 账号。用户提供的规格为 Debian 13、2 vCPU、约 1.7 GiB RAM、40 GiB 磁盘（约 27 GiB 可用）。架构、实际可用资源、现有服务与端口以审计输出为准。该账号有 Docker 组和 sudo 权限，按等效 root 的权限看待。

## 1. 只读审计

优先复用已登录的阿里云控制台。在北京地域确认目标实例的公网 IP 和主机名，检查 ECS 云助手是否可用。若可用，由执行方在云助手中以 `couple-deploy` 身份对该实例立即运行下方脚本，并在控制台读取执行结果。选择「执行」即可，保留常规执行记录。用户只需登录控制台。[阿里云云助手立即执行](https://www.alibabacloud.com/help/en/ecs/user-guide/use-the-immediate-execution-feature)

在可信的阿里云 ECS Workbench 会话中读取 ED25519 主机指纹。也可从对应实例的系统日志查看 `SSH HOST KEY FINGERPRINTS` 段。SSH 连接前将从控制台取得的指纹与目标地址提供的 ED25519 指纹精确比对。匹配后使用专用 known_hosts 和 `StrictHostKeyChecking=yes`。[阿里云主机指纹核验](https://www.alibabacloud.com/help/zh/ecs/user-guide/connect-to-a-linux-instance-by-using-an-ssh-key-pair#verify-the-host-key-fingerprint)

云助手、已核验的 SSH 会话和 Workbench 均可运行以下命令。`sudo -n` 在已有权限可用时补充端口的进程归属。Docker 状态只采集摘要和即时资源用量。

```sh
LC_ALL=C sh <<'COUPLE_AUDIT'
date -Is
hostname
id
uname -m
cat /etc/os-release
printf '\nCPU count and load\n'
nproc
uptime
printf '\nRAM and swap\n'
free -m
cat /proc/swaps
printf '\nDisk\n'
df -hT / "$HOME"
printf '\nDocker and Compose\n'
docker --version
docker compose version
systemctl is-enabled docker.service
systemctl is-active docker.service
docker info --format 'Storage={{.Driver}} Root={{.DockerRootDir}} Cgroup={{.CgroupVersion}}'
docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)
if [ -n "$docker_root" ]; then
  df -hT -- "$docker_root" 2>/dev/null || sudo -n df -hT -- "$docker_root"
fi
printf '\nTCP and UDP listeners\n'
sudo -n ss -ltnup 2>/dev/null || ss -ltnu
printf '\nRunning and failed services\n'
systemctl list-units --type=service --state=running,failed --no-pager
printf '\nTop processes by RSS\n'
ps -eo pid,comm,%cpu,%mem,rss --sort=-rss | head -n 16
printf '\nContainers\n'
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.PIDs}}'
COUPLE_AUDIT
```

汇报中记录 `MemAvailable`、现有容器占用、Swap、Docker 数据盘余量、回环端口是否可用和服务异常。约 1.7 GiB 是待核实的主机规格。容器冷启动、首次聊天和两人并发的峰值留到获批后的验收测量。

## 2. 获得部署授权后启动

建议工作目录为 `/home/couple-deploy/app/couple-ai-demo`。将本项目 `demo/` 中的 `compose.yaml`、`Dockerfile`、`gateway.py`、`requirements.txt`、`.env.example`、`.dockerignore` 上传到独立目录。CLI 上传可复用经核验的 SSH 主机身份与登录凭据。Compose 项目名为 `couple-ai-demo`，启动前核对不存在同名 Compose 项目，且默认回环端口 `4380` 可用。使用仓库中已锁定的 Open WebUI slim 镜像和网关依赖。[Open WebUI 容器安装](https://docs.openwebui.com/getting-started/quick-start/)

在服务器上初始化 `.env`。审计确认需改端口时，同步更新 `DEMO_PORT` 与对应访问源。保留随机生成的两个值，以便重建服务。

```sh
(
  set -eu
  cd /home/couple-deploy/app/couple-ai-demo
  umask 077
  webui_secret=$(openssl rand -hex 32)
  gateway_token=$(openssl rand -hex 32)
  set -C
  sed -e "s/^WEBUI_SECRET_KEY=$/WEBUI_SECRET_KEY=$webui_secret/" \
      -e "s/^DEMO_GATEWAY_TOKEN=$/DEMO_GATEWAY_TOKEN=$gateway_token/" \
      .env.example > .env
)
```

`.env` 初始化成功后，保持 `DEEPSEEK_ENABLED=false`，再执行启动和健康检查。这里的健康检查验证应用进程可用，上游模型验收在下一阶段进行。[Open WebUI 健康检查](https://docs.openwebui.com/reference/monitoring/)

```sh
docker compose config --quiet && docker compose up -d --build
docker compose ps
curl -fsS http://127.0.0.1:4380/health
docker compose exec -T deepseek-gateway python -c \
  "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).read().decode())"
docker compose logs --tail 80 webui deepseek-gateway
free -m
docker compose stats --no-stream
```

可经已验证的 SSH 连接转发 `-L 4380:127.0.0.1:4380`，用 `http://127.0.0.1:4380/health` 做本机健康检查。双手机验收使用获准的私网 HTTPS，实际 URL 由节点 DNS 名和获准端口确定。若现有 Tailnet 启用了 HTTPS，并已核对现有 Serve 入口与访问策略，可选用空闲的 Tailnet HTTPS 端口，例如 `8443`。[Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve)

```sh
tailscale serve status
# 仅在该私网入口获批且 8443 空闲时执行
sudo tailscale serve --bg --https=8443 http://127.0.0.1:4380
```

在服务器编辑 `.env`，设置 `DEMO_WEBUI_ORIGIN` 为实际 HTTPS 源（含端口），保留 `WEBUI_AUTH_COOKIE_SECURE=true`，应用 `docker compose up -d webui`。浏览实际 HTTPS 地址，建立管理员账号和两个普通账号，为两人开放 AI 模型权限，并创建只有两人加入的 Group Channel。公网发布若另获批准，需要在阿里云 ECS 安全组入方向为实际发布端口评估并设置允许来源。

## 3. 获得真实模型调用授权后验收

在服务器上用编辑器打开权限为 `0600` 的 `.env`，填写 `DEEPSEEK_API_KEY` 并设 `DEEPSEEK_ENABLED=true`。密钥由 Compose 注入网关。现有默认值是每天最多 30 次上游尝试，每次最多 1,024 输出 tokens。模型为 `deepseek-flash`。[DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)

```sh
docker compose config --quiet && docker compose up -d deepseek-gateway
docker compose ps
docker compose logs --tail 80 webui deepseek-gateway
```

使用两个普通账号、独立浏览器会话与合成文本，验证各自的私聊权限、共同频道和 `@AI` 回复、第三方访问限制和注册关闭。两部手机实测私网入口。分别记录冷启动、空闲与两人并发时的 RAM、容器峰值、重启次数和错误，结合原有服务负载判断 1.7 GiB 是否够用。

## 4. 重启、停用与回滚

```sh
docker compose restart webui deepseek-gateway
# 首次上线的回滚，保留持久数据卷
docker compose stop
# 若本次新增了上述专用私网 HTTPS 入口，撤销该入口
sudo tailscale serve --bg --https=8443 off
```

只撤销模型调用时，将 `DEEPSEEK_ENABLED` 改回 `false` 并运行 `docker compose up -d deepseek-gateway`。后续升级前保留旧版 Compose 及镜像标识、原 `.env` 和一致的数据卷快照。版本回滚时，在独立恢复卷上恢复与旧版兼容的数据快照，进入已准备好的旧版发布目录，使用旧镜像执行 `docker compose up -d --no-build`。复查健康、账号访问与渠道权限后再接回获准的访问入口。
