# Open Pose & Costume —— 内网静态站点镜像
# 多阶段：Node 构建前端 → nginx 托管 dist/

FROM node:22-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# 构建期可选：Atomflow 代理 / Job API（内网默认留空，自定义供应商走浏览器直连）
ARG VITE_IMAGE_PROXY_URL=
ARG VITE_IMAGE_JOB_API_URL=
ENV VITE_IMAGE_PROXY_URL=$VITE_IMAGE_PROXY_URL \
    VITE_IMAGE_JOB_API_URL=$VITE_IMAGE_JOB_API_URL

RUN npm run build

FROM nginx:1.27-alpine
LABEL org.opencontainers.image.title="open-pose-costume" \
      org.opencontainers.image.description="Open Pose & Costume static web"

ENV TZ=Asia/Shanghai \
    ARK_UPSTREAM=https://ark.cn-beijing.volces.com \
    ARK_HOST=ark.cn-beijing.volces.com

# 配置是模板：启动时只替换 ARK_UPSTREAM / ARK_HOST，保留 nginx 的 $http_* 变量
COPY deploy/nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY deploy/nginx/docker-entrypoint.sh /usr/local/bin/opc-entrypoint.sh
COPY --from=build /app/dist /usr/share/nginx/html

RUN chmod +x /usr/local/bin/opc-entrypoint.sh \
 && envsubst '${ARK_UPSTREAM} ${ARK_HOST}' \
      < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf \
 && nginx -t

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
  CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1

ENTRYPOINT ["/usr/local/bin/opc-entrypoint.sh"]
