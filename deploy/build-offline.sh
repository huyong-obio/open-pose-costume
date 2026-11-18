#!/usr/bin/env bash
# Open Pose & Costume 离线镜像打包（在能联网的开发机上执行）
#
# 用法：
#   bash deploy/build-offline.sh                 # 构建 web 并导出 tar
#   bash deploy/build-offline.sh --no-build      # 只导出已存在的镜像
#   bash deploy/build-offline.sh --gzip          # 额外生成 .tar.gz
#   bash deploy/build-offline.sh --out /tmp/opc-images.tar
#
# 产物：deploy/images/open-pose-costume-images.tar
# 服务器端：bash deploy/install.sh --offline
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

log()  { printf '\n\033[1;34m[%s] %s\033[0m\n' "$(date '+%H:%M:%S')" "$*"; }
info() { printf '  - %s\n' "$*"; }
ok()   { printf '  [OK] %s\n' "$*"; }
die()  { printf '\n\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

OUT_FILE="$REPO_ROOT/deploy/images/open-pose-costume-images.tar"
DO_BUILD=1
DO_GZIP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build)        DO_BUILD=0 ;;
    --gzip)            DO_GZIP=1 ;;
    --out)             OUT_FILE="${2:-}"; shift ;;
    --out=*)           OUT_FILE="${1#*=}" ;;
    -h|--help)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
  shift
done

command -v docker >/dev/null 2>&1 || die "没有 docker 命令，请在装有 Docker 的开发机上执行"
docker info >/dev/null 2>&1 || die "Docker 守护进程不可用（Linux 上可能需要 sudo）"
docker compose version >/dev/null 2>&1 || die "缺少 docker compose v2 插件"

IMAGES=(open-pose-costume-web:latest)

if [ "$DO_BUILD" -eq 1 ]; then
  log "1/3 构建镜像"
  docker compose build web
  ok "构建完成"
else
  log "1/3 跳过构建（--no-build）"
fi

log "2/3 校验镜像"
for img in "${IMAGES[@]}"; do
  docker image inspect "$img" >/dev/null 2>&1 || die "找不到镜像 $img，请先执行构建"
  info "$img"
done

log "3/3 导出镜像"
mkdir -p "$(dirname "$OUT_FILE")"
info "目标文件：$OUT_FILE"
docker save -o "$OUT_FILE" "${IMAGES[@]}"
ok "导出完成：$(du -h "$OUT_FILE" | awk '{print $1}')"

if [ "$DO_GZIP" -eq 1 ]; then
  info "压缩中……"
  gzip -c "$OUT_FILE" > "${OUT_FILE}.gz"
  ok "压缩完成：${OUT_FILE}.gz（$(du -h "${OUT_FILE}.gz" | awk '{print $1}')）"
  info "服务器端可直接 docker load -i ${OUT_FILE}.gz（install.sh --offline 会自动识别）"
fi

printf '\n镜像清单：\n'
for img in "${IMAGES[@]}"; do
  docker image inspect "$img" --format '  {{.RepoTags}}  {{.Size}} bytes' 2>/dev/null || true
done

printf '\n拷贝到服务器后执行：\n'
printf '  scp %s user@server:/opt/open-pose-costume/deploy/images/\n' \
  "$([ "$DO_GZIP" -eq 1 ] && echo "${OUT_FILE}.gz" || echo "$OUT_FILE")"
printf '  bash deploy/install.sh --offline\n'
