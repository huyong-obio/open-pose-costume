#!/usr/bin/env bash
# Open Pose & Costume 卸载脚本
#
# 用法：
#   bash deploy/uninstall.sh                 # 停止并删除容器与网络，保留镜像
#   bash deploy/uninstall.sh --purge-images  # 同时删除 open-pose-costume-web 镜像
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

log()  { printf '\n\033[1;34m[%s] %s\033[0m\n' "$(date '+%H:%M:%S')" "$*"; }
info() { printf '  - %s\n' "$*"; }
ok()   { printf '  [OK] %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }
die()  { printf '\n\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

PURGE_IMAGES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --purge-images) PURGE_IMAGES=1 ;;
    -h|--help)      sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
  shift
done

DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    die "无法访问 Docker"
  fi
fi

log "1/2 停止并删除容器"
"${DOCKER[@]}" compose down --remove-orphans || warn "compose down 报错（可能本来就没在运行），继续"
ok "容器已清理"

if [ "$PURGE_IMAGES" -eq 1 ]; then
  log "2/2 删除镜像"
  if "${DOCKER[@]}" image inspect open-pose-costume-web:latest >/dev/null 2>&1; then
    "${DOCKER[@]}" rmi open-pose-costume-web:latest \
      && ok "已删除 open-pose-costume-web:latest" \
      || warn "删除镜像失败（可能仍被容器引用）"
  else
    info "open-pose-costume-web:latest 不存在，跳过"
  fi
else
  log "2/2 保留镜像（加 --purge-images 可删除）"
fi

printf '\n卸载完成。\n'
