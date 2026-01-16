# Xray Tunnel Docker 部署

基于 Alpine Linux 的 Xray + Cloudflare Tunnel Docker 镜像，适合无开放端口的容器化平台部署。

## 快速开始

### 1. 前置准备

在 [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) 控制台：
- 创建 Tunnel
- 配置 Public Hostname：`your.domain.com` → `http://localhost:端口号`

### 2. 运行容器

```bash
docker run -d \
  --name xray-tunnel \
  --restart unless-stopped \
  -e CF_TOKEN="your_cloudflare_token" \
  -e DOMAIN="your.domain.com" \
  -e PORT="443" \
  ghcr.io/audsiui/xray-jb:latest
```

### 3. 获取连接信息

查看容器日志获取 `vless://` 链接和二维码：

```bash
docker logs xray-tunnel
```

## 环境变量

| 变量 | 必需 | 说明 | 示例 |
|------|------|------|------|
| `CF_TOKEN` | ✅ | Cloudflare Tunnel token | `eyJhbGciOi...` |
| `DOMAIN` | ✅ | 你的域名（需在 CF 配置） | `v.example.com` |
| `PORT` | ✅ | 监听端口（需匹配 CF 配置） | `443` |
| `OPT_DOMAIN` | ❌ | 优选域名（默认 cf.tencentapp.cn） | `cf.iptv.com` |

## 部署平台

### Docker
```bash
docker run -d \
  --name xray-tunnel \
  --restart unless-stopped \
  -e CF_TOKEN="xxx" \
  -e DOMAIN="xxx.com" \
  -e PORT="443" \
  ghcr.io/audsiui/xray-jb:latest
```

### Docker Compose
```yaml
version: '3.8'
services:
  xray-tunnel:
    image: ghcr.io/audsiui/xray-jb:latest
    container_name: xray-tunnel
    restart: unless-stopped
    environment:
      CF_TOKEN: "your_token"
      DOMAIN: "your.domain.com"
      PORT: "443"
      OPT_DOMAIN: "cf.tencentapp.cn"
```

### Kubernetes
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: xray-tunnel
spec:
  containers:
  - name: xray-tunnel
    image: ghcr.io/audsiui/xray-jb:latest
    env:
    - name: CF_TOKEN
      value: "your_token"
    - name: DOMAIN
      value: "your.domain.com"
    - name: PORT
      value: "443"
```

### Fly.io
```toml
[build]
  image = "ghcr.io/audsiui/xray-jb:latest"

[env]
  CF_TOKEN = "your_token"
  DOMAIN = "your.domain.com"
  PORT = "443"
```

### Railway
设置环境变量后直接部署镜像即可。

## 查看配置

容器启动后，配置信息保存在 `/opt/xray-bundle/.info`：

```bash
docker exec xray-tunnel cat /opt/xray-bundle/.info
```

输出：
```
UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
WS_PATH=abcd
DOMAIN=your.domain.com
OPT_DOMAIN=cf.tencentapp.cn
PORT=443
```

## 镜像架构

- `linux/amd64` - x86_64
- `linux/arm64` - ARM64/aarch64

## 注意事项

1. **端口匹配**：`PORT` 环境变量必须与 Cloudflare Tunnel 控制台配置的端口一致
2. **无端口暴露**：容器内 Xray 监听 `127.0.0.1`，无需映射端口到宿主机
3. **进程管理**：容器内同时运行 Xray 和 cloudflared 两个进程，使用信号处理优雅关闭
4. **健康检查**：内置健康检查，两个进程都正常运行时容器状态才为 healthy

## 故障排查

### 查看日志
```bash
docker logs -f xray-tunnel
```

### 进入容器
```bash
docker exec -it xray-tunnel sh
```

### 检查进程
```bash
docker exec xray-tunnel ps aux
```

## 镜像源码

[GitHub](https://github.com/audsiui/xray-jb)
