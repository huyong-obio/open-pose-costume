# Open Pose & Costume 内网部署手册（Docker）

> **第一次部署请直接看 [FIRST-DEPLOY.md](./FIRST-DEPLOY.md)**。本文是参考手册。

部署形态：单个 `web` 容器（nginx 托管 Vite 构建产物）。

| 服务 | 作用 | 对外端口 |
| --- | --- | --- |
| `web` | 静态站点 + SPA 路由 | `5200`（可用 `OPC_PORT` 改） |

生图请求由**浏览器**发往你在设置里填写的服务地址；本容器不保存 API Key。

---

## 0. 一页速查

**在线**

```bash
cd /opt/open-pose-costume
cp .env.example .env
bash deploy/install.sh
```

**离线**

```bash
# 开发机
bash deploy/build-offline.sh --gzip
# 把仓库 + deploy/images/*.tar.gz 拷到服务器后
bash deploy/install.sh --offline
```

---

## 1. 前置条件

| 项目 | 要求 |
| --- | --- |
| 系统 | Ubuntu 20.04 / 22.04 / 24.04（Debian 亦可） |
| Docker | 24.0+，compose v2 |
| 内存 | 建议 ≥ 1 GB（镜像构建阶段建议 ≥ 2 GB） |
| 磁盘 | 建议 ≥ 5 GB（含构建缓存） |
| 架构 | x86_64 / arm64；离线镜像须与服务器同架构 |

---

## 2. 环境变量（`.env`）

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `OPC_PORT` | `5200` | 宿主机对外端口 |
| `OPC_BIND_IP` | `0.0.0.0` | 绑定地址 |
| `TZ` | `Asia/Shanghai` | 容器时区 |
| `VITE_IMAGE_PROXY_URL` | 空 | 构建期 Atomflow 代理地址；内网验证自定义供应商通常留空 |
| `VITE_IMAGE_JOB_API_URL` | 空 | 构建期 Job API；留空则浏览器直连供应商 |

改了 `VITE_*` 必须重新 `docker compose build`，仅重启无效。

---

## 3. 安装脚本参数

```bash
bash deploy/install.sh --help
```

| 参数 | 作用 |
| --- | --- |
| `--offline` | 从 `deploy/images/*.tar(.gz)` 导入镜像 |
| `--port N` | 本次覆盖 `OPC_PORT`（长期请改 `.env`） |
| `--docker-mirror URL` | 写入 Docker registry 加速器 |
| `--no-docker-install` | 缺 Docker 时直接失败 |

---

## 4. 常用运维

```bash
docker compose ps
docker compose logs -f --tail=200
docker compose restart
bash deploy/uninstall.sh                 # 停容器，保留镜像
bash deploy/uninstall.sh --purge-images  # 连镜像一起删
```

升级：

```bash
cd /opt/open-pose-costume
git pull
bash deploy/install.sh
```

---

## 5. 自定义供应商说明

设置页提供三个必填项：

1. **服务地址（Base URL）**
2. **API Key**
3. **模型名称**

可选预设：OpenWego / Atomflow / 火山方舟。

| 类型 | Base URL 示例 | 实际请求 |
| --- | --- | --- |
| OpenAI 兼容 | `https://api.example.com/v1` | `…/v1/images/edits`（multipart） |
| 火山方舟 | `https://ark.cn-beijing.volces.com/api/v3` | `…/api/v3/images/generations`（JSON + Bearer） |

火山方舟注意：

- **不要**在 Base URL 后再加 `/v1`（已自动纠正为 `/api/v3/images/generations`）
- 模型请填控制台 **Model ID**（如 `doubao-seedream-5-0-flash-260915`），不要填 `Doubao-Seedream-5.0-flash` 这类展示名，也不要漏掉日期后缀
- 火山方舟接口本身放行浏览器 CORS（会回显 Origin 并允许 `Authorization`），所以前端默认**直连** `https://ark.cn-beijing.volces.com`
- 只有直连被内网网关拦截时，才退回同源 `/opc-proxy/ark/...` 代理；该代理只用于兜底，失败时返回 JSON（`proxy_unavailable`）而不是 nginx 的 HTML 错误页

---

## 6. 故障排查

| 现象 | 处理 |
| --- | --- |
| `port is already allocated` | 改 `.env` 的 `OPC_PORT`，再跑 `install.sh` |
| 构建失败 / npm 超时 | 走离线：`build-offline.sh --gzip` + `install.sh --offline` |
| 页面白屏 | `docker compose logs web`；确认 `dist` 构建成功 |
| 生图 CORS 失败 | 火山方舟本身允许 CORS；其他供应商不放行当前站点 Origin 时，改用内网兼容网关，或在网关侧加 CORS |
| 生图报 500/502（HTML 错误页） | 是 nginx 代理而非模型问题：`docker compose logs --tail=100 web`，确认容器能解析并访问 `ark.cn-beijing.volces.com`；新版前端默认直连，代理只兜底 |
| `exec format error` | 离线镜像架构与服务器不一致，在同架构机器重打镜像 |
