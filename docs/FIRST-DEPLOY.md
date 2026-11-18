# Open Pose & Costume 首次部署实操（Ubuntu 内网）

这份文档是**照着敲**的：从一台公司内网 Ubuntu 虚拟机开始，部署本站点，
并验证「自定义供应商」三字段（Base URL / API Key / Model）可用。

日常运维与排障见 [`docs/DEPLOYMENT.md`](./DEPLOYMENT.md)。

---

## 适用场景

- 目标机器：公司内网 **Ubuntu 20.04 / 22.04 / 24.04**
- 部署形态：单个 `web` 容器（nginx 托管静态站点）
- 生图：浏览器填写自定义供应商的 **服务地址、API Key、模型名称**；密钥只存在浏览器本地

## 开始前定 2 件事

| 要定的事 | 怎么定 | 影响 |
| --- | --- | --- |
| **① 服务器内网 IP** | `hostname -I` | 浏览器访问地址 |
| **② 对外端口** | 默认 `5200`；查占用：`sudo ss -lntp \| grep 5200` | `.env` 的 `OPC_PORT` |

---

## 阶段 1：登录与体检

```bash
ssh deploy@192.168.x.x
whoami
cat /etc/os-release | head -n 3
uname -m
sudo -v && echo "sudo OK"
```

出网检查（决定在线 / 离线）：

```bash
curl -sS -o /dev/null -w 'get.docker.com        %{http_code}\n' --max-time 8 https://get.docker.com
curl -sS -o /dev/null -w 'docker hub registry  %{http_code}\n' --max-time 8 https://registry-1.docker.io/v2/
curl -sS -o /dev/null -w 'npm registry         %{http_code}\n' --max-time 8 https://registry.npmjs.org/
```

- 都能通 → **在线**（`bash deploy/install.sh`）
- Docker 通、npm 不通 → **混合**：开发机 `bash deploy/build-offline.sh --gzip`，服务器 `--offline`
- Docker 也不通 → **完全离线**：服务器需先有 Docker，再用 `--offline`

---

## 阶段 2：拿代码

```bash
sudo mkdir -p /opt/open-pose-costume
sudo chown "$USER":"$USER" /opt/open-pose-costume
cd /opt/open-pose-costume
git clone https://github.com/huyong-obio/open-pose-costume.git .
git rev-parse --short HEAD
```

离线时也可在开发机打包后 scp：

```bash
# 开发机
tar --exclude='.git' --exclude='node_modules' --exclude='dist' \
    --exclude='deploy/images' -czf /tmp/opc-src.tar.gz .
scp /tmp/opc-src.tar.gz deploy@192.168.x.x:/tmp/
# 若离线部署，同时传镜像包
# scp deploy/images/open-pose-costume-images.tar.gz deploy@192.168.x.x:/tmp/
```

```bash
# 服务器
cd /opt/open-pose-costume
tar -xzf /tmp/opc-src.tar.gz
mkdir -p deploy/images
# mv /tmp/open-pose-costume-images.tar.gz deploy/images/   # 仅离线
```

---

## 阶段 3：配置与安装

```bash
cd /opt/open-pose-costume
cp .env.example .env
chmod 600 .env
# 按需改端口：OPC_PORT=5200
```

在线：

```bash
bash deploy/install.sh
# 或指定端口：bash deploy/install.sh --port 8080
```

离线：

```bash
bash deploy/install.sh --offline
```

**判据**：出现 `[OK] 健康检查通过` 与 `[7/7] 部署完成`；`docker compose ps` 中 `web` 为 `Up ... (healthy)`。

---

## 阶段 4：验证

### 4.1 站点可达

```bash
curl -fsS http://127.0.0.1:5200/healthz; echo
# 预期：ok
```

浏览器打开：`http://<服务器IP>:5200/`

### 4.2 验证自定义供应商三字段（本次改动）

1. 打开站点，进入「一键生图」
2. 点击右上角 **生图设置**（齿轮）
3. 确认表单始终可见并可编辑：
   - **服务地址（Base URL）**
   - **API Key**
   - **模型名称**
4. 可选：点击 OpenWego / Atomflow 预设，确认会自动填入地址与模型，仍可手工改成任意兼容服务
5. 填入你的内网或兼容 OpenAI `/v1/images/edits` 的服务后点「保存配置」
6. 搭配姿势 + 服饰后尝试生成（需该服务可从你的浏览器访问，并允许 CORS）

---

## 交付清单

- [ ] `docker compose ps` → `web` 为 healthy
- [ ] `curl http://127.0.0.1:5200/healthz` → `ok`
- [ ] 浏览器首页正常渲染
- [ ] 生图设置可填写 Base URL / API Key / Model 并保存
- [ ] 记下版本：`git -C /opt/open-pose-costume rev-parse --short HEAD`
