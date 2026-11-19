#!/usr/bin/env bash
# Open Pose & Costume 一键部署脚本（Ubuntu / Debian）
#
# 用法：
#   bash deploy/install.sh                      # 在线构建并启动
#   bash deploy/install.sh --port 8080          # 覆盖对外端口
#   bash deploy/install.sh --offline            # 从 deploy/images/*.tar 导入镜像，不构建
#   bash deploy/install.sh --docker-mirror https://docker.mirrors.ustc.edu.cn
#   bash deploy/install.sh --no-docker-install  # 缺少 Docker 时直接报错
#
# 幂等：重复执行只会重建/重启容器，不会执行 docker compose down -v。
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true

log()  { printf '\n\033[1;34m[%s] %s\033[0m\n' "$(date '+%H:%M:%S')" "$*"; }
info() { printf '  - %s\n' "$*"; }
ok()   { printf '  [OK] %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }
die()  { printf '\n\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Open Pose & Costume 一键部署脚本（Ubuntu / Debian）

用法：bash deploy/install.sh [选项]

  (无选项)                 在线构建镜像并启动 web
  --offline                不构建，从 deploy/images/*.tar(.gz) 导入镜像
  --port N                 覆盖对外端口（等价于 OPC_PORT=N）
  --docker-mirror URL      写入 /etc/docker/daemon.json 的镜像加速器
  --no-docker-install      缺少 Docker 时直接报错，不尝试自动安装
  --no-cache               构建时禁用 Docker 缓存（代理/nginx 配置未生效时用）
  -h, --help               显示本帮助

示例：
  bash deploy/install.sh
  bash deploy/install.sh --no-cache
  bash deploy/install.sh --port 8080
  bash deploy/install.sh --offline
EOF
}

OFFLINE=0
PORT=""
DOCKER_MIRROR=""
ALLOW_NO_DOCKER_INSTALL=0
NO_CACHE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --offline)             OFFLINE=1 ;;
    --port)                PORT="${2:-}"; shift ;;
    --port=*)              PORT="${1#*=}" ;;
    --docker-mirror)       DOCKER_MIRROR="${2:-}"; shift ;;
    --docker-mirror=*)     DOCKER_MIRROR="${1#*=}" ;;
    --no-docker-install)   ALLOW_NO_DOCKER_INSTALL=1 ;;
    --no-cache)            NO_CACHE=1 ;;
    -h|--help)             usage; exit 0 ;;
    *)                     die "未知参数：$1（用 --help 查看用法）" ;;
  esac
  shift
done

if [ -n "$PORT" ]; then
  case "$PORT" in
    ''|*[!0-9]*) die "--port 需要是数字，例如 --port 8080" ;;
  esac
  export OPC_PORT="$PORT"
fi

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  SUDO=()
  warn "当前不是 root 且没有 sudo，安装 Docker 会失败；如果需要安装请用 root 运行"
fi

as_root() {
  if [ "${#SUDO[@]}" -gt 0 ]; then "${SUDO[@]}" "$@"; else "$@"; fi
}

# ---------------------------------------------------------------- 1. 系统检查
log "1/7 检查系统环境"
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  info "发行版：${PRETTY_NAME:-未知}"
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) warn "非 Ubuntu/Debian，脚本里的 apt 安装步骤可能不适用" ;;
  esac
else
  warn "读不到 /etc/os-release，按 Debian 系继续"
fi
info "内核：$(uname -r)"
info "架构：$(uname -m)"

# ---------------------------------------------------------------- 2. Docker
log "2/7 检查 Docker Engine 与 compose 插件"

if [ -n "$DOCKER_MIRROR" ]; then
  info "写入镜像加速器：$DOCKER_MIRROR"
  as_root mkdir -p /etc/docker
  if [ -f /etc/docker/daemon.json ] && [ -s /etc/docker/daemon.json ]; then
    warn "/etc/docker/daemon.json 已存在，未覆盖。请手工把 registry-mirrors 合并进去："
    info "{\"registry-mirrors\": [\"$DOCKER_MIRROR\"]}"
  else
    printf '{\n  "registry-mirrors": ["%s"]\n}\n' "$DOCKER_MIRROR" | as_root tee /etc/docker/daemon.json >/dev/null
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      as_root systemctl restart docker 2>/dev/null || warn "重启 docker 失败，请手工执行 systemctl restart docker"
      sleep 2
    fi
  fi
fi

if ! command -v docker >/dev/null 2>&1; then
  if [ "$ALLOW_NO_DOCKER_INSTALL" -eq 1 ]; then
    die "未安装 Docker，且指定了 --no-docker-install"
  fi
  info "未检测到 Docker，开始安装（官方脚本，需要外网）"
  as_root apt-get update -y
  as_root apt-get install -y ca-certificates curl gnupg
  curl -fsSL https://get.docker.com -o /tmp/opc-get-docker.sh \
    || die "下载 Docker 安装脚本失败，请检查网络或手工安装 Docker 24+"
  as_root sh /tmp/opc-get-docker.sh
  as_root systemctl enable --now docker 2>/dev/null || warn "systemctl 不可用，请确认 dockerd 已启动"
  if [ "$(id -u)" -ne 0 ] && [ -n "${SUDO_USER:-}" ]; then
    as_root usermod -aG docker "$SUDO_USER" 2>/dev/null || true
    warn "已把 $SUDO_USER 加入 docker 组，重新登录后才可以免 sudo 使用 docker"
  fi
fi

if ! docker info >/dev/null 2>&1; then
  if [ "${#SUDO[@]}" -gt 0 ] && "${SUDO[@]}" docker info >/dev/null 2>&1; then
    DOCKER=("${SUDO[@]}" docker)
    warn "当前用户不在 docker 组，本脚本后续 docker 命令自动加 sudo"
  else
    die "无法连接 Docker 守护进程，请确认 docker 服务已启动（systemctl status docker）"
  fi
else
  DOCKER=(docker)
fi

if ! "${DOCKER[@]}" compose version >/dev/null 2>&1; then
  info "缺少 docker compose 插件，尝试安装"
  as_root apt-get update -y
  as_root apt-get install -y docker-compose-plugin \
    || die "安装 docker-compose-plugin 失败，请手工安装 compose v2"
fi
ok "Docker $("${DOCKER[@]}" --version | awk '{print $3}' | tr -d ',')"
ok "compose $("${DOCKER[@]}" compose version --short)"

COMPOSE=("${DOCKER[@]}" compose)

# ---------------------------------------------------------------- 3. .env
log "3/7 检查 .env"
if [ ! -f "$REPO_ROOT/.env" ]; then
  if [ -f "$REPO_ROOT/.env.example" ]; then
    cp "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"
    chmod 600 "$REPO_ROOT/.env"
    ok "已从 .env.example 生成 .env"
  else
    cat >"$REPO_ROOT/.env" <<'EOF'
# Open Pose & Costume 内网部署
OPC_PORT=5200
OPC_BIND_IP=0.0.0.0
TZ=Asia/Shanghai
# 构建期可选；内网验证自定义供应商时通常留空
VITE_IMAGE_PROXY_URL=
VITE_IMAGE_JOB_API_URL=
EOF
    chmod 600 "$REPO_ROOT/.env"
    ok "已生成默认 .env"
  fi
else
  ok ".env 已存在"
fi

# ---------------------------------------------------------------- 4. 镜像
log "4/7 准备镜像"
if [ "$OFFLINE" -eq 1 ]; then
  shopt -s nullglob
  archives=("$REPO_ROOT"/deploy/images/*.tar "$REPO_ROOT"/deploy/images/*.tar.gz)
  shopt -u nullglob
  [ "${#archives[@]}" -gt 0 ] || die "deploy/images/ 下没有 *.tar 或 *.tar.gz，请先在开发机执行 bash deploy/build-offline.sh"
  for archive in "${archives[@]}"; do
    info "导入 $(basename "$archive")"
    "${DOCKER[@]}" load -i "$archive"
  done
  "${DOCKER[@]}" image inspect open-pose-costume-web:latest >/dev/null 2>&1 \
    || die "导入后仍找不到 open-pose-costume-web:latest，镜像包内容与 compose 不匹配"
  ok "镜像导入完成"
else
  info "开始构建（首次会比较久，需要能访问 npm registry）"
  if [ "$NO_CACHE" -eq 1 ]; then
    "${COMPOSE[@]}" build --no-cache web
  else
    "${COMPOSE[@]}" build web
  fi
  ok "构建完成"
fi

# ---------------------------------------------------------------- 5. 启动
log "5/7 启动服务"
"${COMPOSE[@]}" up -d --force-recreate --no-build
ok "容器已启动"

# ---------------------------------------------------------------- 6. 健康检查
log "6/7 等待 /healthz 返回 200"

web_addr="$("${COMPOSE[@]}" port web 80 2>/dev/null | head -n 1 || true)"
if [ -n "$web_addr" ]; then
  EFFECTIVE_PORT="${web_addr##*:}"
else
  EFFECTIVE_PORT="${OPC_PORT:-5200}"
fi

health_ok() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 3 "http://127.0.0.1:${EFFECTIVE_PORT}/healthz" >/dev/null 2>&1 && return 0
  fi
  "${COMPOSE[@]}" exec -T web wget -q -O /dev/null http://127.0.0.1/healthz >/dev/null 2>&1
}

proxy_ok() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 3 "http://127.0.0.1:${EFFECTIVE_PORT}/opc-proxy/ark/healthz" >/dev/null 2>&1 && return 0
  fi
  "${COMPOSE[@]}" exec -T web wget -q -O /dev/null http://127.0.0.1/opc-proxy/ark/healthz >/dev/null 2>&1
}

healthy=0
for _ in $(seq 1 40); do
  if health_ok; then healthy=1; break; fi
  sleep 3
done

if [ "$healthy" -ne 1 ]; then
  warn "健康检查超时（120 秒）。当前容器状态："
  "${COMPOSE[@]}" ps || true
  warn "最近日志："
  "${COMPOSE[@]}" logs --tail=50 || true
  die "服务未能正常启动，请按上面的日志排查（参考 docs/DEPLOYMENT.md）"
fi
ok "健康检查通过"

if proxy_ok; then
  ok "火山代理路由已就绪（/opc-proxy/ark/healthz）"
else
  warn "未检测到 /opc-proxy/ark/healthz。若生图报 404，请执行：bash deploy/install.sh --no-cache"
fi

# ---------------------------------------------------------------- 7. 汇总
log "7/7 部署完成"
"${COMPOSE[@]}" ps

host_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
[ -n "$host_ip" ] || host_ip="<服务器IP>"

printf '\n访问地址：\n'
printf '  前端站点     http://%s:%s/\n' "$host_ip" "$EFFECTIVE_PORT"
printf '  健康检查     http://%s:%s/healthz\n' "$host_ip" "$EFFECTIVE_PORT"
printf '  火山代理探测 http://%s:%s/opc-proxy/ark/healthz\n' "$host_ip" "$EFFECTIVE_PORT"
printf '  生图设置     打开站点后点击右上角齿轮，填写 Base URL / API Key / Model\n'
printf '\n常用命令：\n'
printf '  %s logs -f --tail=200    查看日志\n' "${COMPOSE[*]}"
printf '  %s restart               重启\n' "${COMPOSE[*]}"
printf '  bash deploy/uninstall.sh 卸载容器（默认保留镜像）\n'
printf '\n验证自定义供应商：打开生图设置，确认可填写服务地址、API Key、模型名称并保存。\n'
