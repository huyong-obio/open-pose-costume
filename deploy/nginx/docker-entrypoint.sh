#!/bin/sh
# 只替换 ARK_UPSTREAM / ARK_HOST，避免把 nginx 的 $http_* 变量一起替换掉。
set -eu

ARK_UPSTREAM="${ARK_UPSTREAM:-https://ark.cn-beijing.volces.com}"
ARK_HOST="${ARK_HOST:-ark.cn-beijing.volces.com}"
export ARK_UPSTREAM ARK_HOST

mkdir -p /etc/nginx/conf.d
envsubst '${ARK_UPSTREAM} ${ARK_HOST}' \
  < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/conf.d/default.conf

echo "nginx: ARK_UPSTREAM=${ARK_UPSTREAM} ARK_HOST=${ARK_HOST}"

nginx -t
exec nginx -g 'daemon off;'
