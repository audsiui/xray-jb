# Xray VLESS 部署脚本

![Shell](https://img.shields.io/badge/shell-bash-blue)
![License](https://img.shields.io/github/license/audsiui/xray-jb)

Xray 多模式一键安装，支持 VLESS+WS/VLESS+REALITY/VLESS+XHTTP 等多种协议，可在同一进程中同时运行。

## 快速开始

### 使用配置生成器（推荐）

访问 [在线配置生成器](https://audsiui.github.io/xray-jb/generator.html) 生成安装命令：

1. 选择协议类型（WS/XHTTP/REALITY/CF Tunnel）
2. 填写配置参数
3. 复制生成的命令到服务器执行

### 直接运行

```bash
bash <(curl -sL https://raw.githubusercontent.com/audsiui/xray-jb/main/main.sh)
```

## 支持的协议

| 模式 | 协议 | 默认端口 | 说明 |
|------|------|----------|------|
| direct | VLESS + WebSocket | 8080 | 传统直连模式，适合配合 CDN |
| tunnel | VLESS + WebSocket + CF Tunnel | 10086 | 内网穿透，无需公网 IP |
| reality | VLESS + REALITY | 8443 | 新型直连，TLS 指纹伪装 |
| xhttp | VLESS + XHTTP | 8081 | 新型 HTTP 传输协议 |

## 命令行参数

| 参数 | 说明 |
|------|------|
| `-m, --mode` | 安装模式: `direct`/`tunnel`/`reality`/`xhttp`/`uninstall`/`manage`/`update` |
| `-p, --port` | 端口号 |
| `-d, --domain` | 域名 (tunnel 模式必需，reality 模式可选) |
| `-t, --token` | Cloudflare Tunnel Token (tunnel 模式必需) |
| `--opt-domain` | 优选域名 (tunnel 模式可选，默认 `cf.tencentapp.cn`) |
| `-a, --action` | 服务操作: `start`/`stop`/`restart`/`status` |
| `-q, --quiet` | 静默模式 |
| `-h, --help` | 帮助 |

## 安装示例

```bash
# 直连模式
bash main.sh --mode direct --port 8080

# REALITY 模式
bash main.sh --mode reality --port 8443 --domain www.microsoft.com

# XHTTP 模式
bash main.sh --mode xhttp --port 8081

# 隧道模式
bash main.sh --mode tunnel --domain example.com --token xxxx

# 四种模式可以共存安装
bash main.sh --mode direct --port 8080
bash main.sh --mode xhttp --port 8081
bash main.sh --mode reality --port 8443
bash main.sh --mode tunnel --port 10086 --domain xxx --token xxx
```

## 服务管理

```bash
# 交互式菜单
bash main.sh  # 选择 5

# 命令行
bash main.sh --manage --action status
bash main.sh --manage --action restart
```

**手动管理服务:**

Systemd: `systemctl start/stop/restart/status xray`
OpenRC: `rc-service xray start/stop/restart/status`

服务名: `xray`(主服务) / `cloudflared-t`(CF Tunnel，仅隧道模式)

## 日志

**位置**: `/opt/xray-bundle/logs/`

```bash
# 实时查看
tail -f /opt/xray-bundle/logs/xray.log

# systemd 额外日志
journalctl -u xray -f
```

日志自动轮转，保留 3 个备份。

## 文件路径

```
/opt/xray-bundle/
├── config.json          # 统一配置文件（所有入站）
├── .direct_info         # 直连模式信息
├── .domain_info         # 隧道模式信息
├── .reality_keys        # REALITY 密钥信息
├── .xhttp_info          # XHTTP 模式信息
├── xray                # Xray 程序
├── cloudflared         # CF Tunnel 程序
└── logs/               # 日志目录
```

## 共存说明

本脚本采用**单进程多入站**架构：

- **一个 Xray 进程**同时处理所有协议的入站连接
- **统一配置文件** (`config.json`) 包含所有入站配置
- 每种模式的数据保存在各自的 `.xxx_info` 文件中
- 安装新模式时会自动重启 Xray 服务应用配置

## 优选域名

隧道模式默认使用 `cf.tencentapp.cn`，可通过 `--opt-domain` 自定义。

## 注意事项

1. 防火墙需放行所选端口 (TCP)
2. 不同模式需使用不同端口避免冲突
3. Alpine 会自动安装兼容包 (`gcompat` 等)

## License

MIT
