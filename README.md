# Xray VLESS 工程化部署脚本

轻量级、模块化的 Xray (VLESS + WebSocket) 一键安装脚本。

专为 **Alpine Linux** 优化，同时完美支持 Debian、Ubuntu 和 CentOS。

## 特性

- **模块化架构** - 库文件与核心逻辑分离，易于维护和扩展
- **双模式支持** - 直连模式 + Cloudflare Tunnel 内网穿透
- **智能系统识别** - 自动检测包管理器 (`apk`/`apt`/`yum`) 和服务管理器 (systemd/OpenRC)
- **智能 IP 识别** - 多 API 轮询，支持 IPv4/IPv6 回退和本地路由兜底
- **端口占用检测** - 安装前自动检测端口是否被占用
- **安全隐蔽** - 自动生成 UUID，动态 WebSocket 路径（4 位随机字符）
- **交互式配置** - 支持自定义端口，带输入验证和错误回滚
- **非交互模式** - 支持命令行参数，适合自动化部署
- **服务管理** - 内置服务管理菜单，支持启停、状态查看、配置链接查看
- **版本更新** - 一键更新 Xray 和 cloudflared 到最新版本
- **二维码显示** - 支持终端内显示配置二维码（需 qrencode）
- **优选域名** - 支持自定义优选域名，默认使用 `cf.tencentapp.cn`

## 快速开始

### 一键运行（交互模式）

```bash
bash <(curl -sL https://raw.githubusercontent.com/audsiui/xray-jb/main/main.sh)
```

运行后会显示交互菜单：

```
------------------------------------------------
  Xray + Tunnel 工程化部署脚本
------------------------------------------------
  1. 安装 VLESS + WS (直连模式)
  2. 安装 VLESS + WS + CF Tunnel (内网穿透)
  3. 服务管理
  4. 更新 Xray/cloudflared 版本
  5. 卸载并清除所有内容
  0. 退出
------------------------------------------------
```

### 命令行模式（非交互）

```bash
# 直连模式安装
bash main.sh --mode direct --port 443

# 隧道模式安装（使用默认优选域名）
bash main.sh --mode tunnel --port 10086 --domain example.com --token xxxx

# 隧道模式安装（使用自定义优选域名）
bash main.sh --mode tunnel --port 10086 --domain example.com --token xxxx --opt-domain my优选域名.com

# 安装并显示二维码
bash main.sh --mode direct --port 443 --qr

# 服务管理
bash main.sh --manage --action status
bash main.sh --manage --action restart

# 更新版本
bash main.sh --update

# 卸载
bash main.sh --mode uninstall

# 查看帮助
bash main.sh --help
```

## 命令行参数

| 参数 | 说明 |
|------|------|
| `-m, --mode <MODE>` | 安装模式: `direct`(直连), `tunnel`(CF隧道), `uninstall`(卸载), `manage`(管理), `update`(更新) |
| `-p, --port <PORT>` | 端口号 (直连默认 8080, 隧道默认 10086) |
| `-d, --domain <DOMAIN>` | 域名 (tunnel 模式必需) |
| `-t, --token <TOKEN>` | Cloudflare Tunnel Token (tunnel 模式必需) |
| `--opt-domain <DOMAIN>` | 优选域名 (tunnel 模式可选，默认 `cf.tencentapp.cn`) |
| `-M, --manage` | 进入服务管理子菜单 |
| `-a, --action <ACTION>` | 服务操作: `start`, `stop`, `restart`, `status` |
| `-u, --update` | 更新 Xray 和 cloudflared 到最新版本 |
| `--uninstall` | 卸载所有服务并清理文件 |
| `-q, --quiet` | 静默模式，减少输出 |
| `--qr` | 安装完成后显示二维码 (需 qrencode) |
| `-h, --help` | 显示帮助信息 |

## 安装模式

### 直连模式

适用于有公网 IP 的服务器：
- Xray 监听 `0.0.0.0:端口`
- 输出带公网 IP 的 `vless://` 链接

```bash
# 交互式安装
bash main.sh
# 选择 1

# 命令行安装
bash main.sh --mode direct --port 443
```

### Tunnel 模式

适用于无公网 IP 或需隐藏真实 IP：
- Xray 仅监听 `127.0.0.1:端口`（本地）
- 通过 Cloudflare Tunnel 暴露
- 需提供 CF Tunnel Token
- 支持自定义优选域名

```bash
# 交互式安装
bash main.sh
# 选择 2

# 命令行安装（使用默认优选域名）
bash main.sh --mode tunnel --domain example.com --token xxxx

# 命令行安装（使用自定义优选域名）
bash main.sh --mode tunnel --domain example.com --token xxxx --opt-domain my优选域名.com
```

## 服务管理

### 服务管理菜单

```
------------------------------------------------
  服务管理
------------------------------------------------
  1. 查看服务状态
  2. 启动服务
  3. 停止服务
  4. 重启服务
  5. 查看详细状态
  6. 查看配置链接
  7. 显示配置二维码
  0. 返回主菜单
------------------------------------------------
```

### 文件路径

- **工作目录**: `/opt/xray-bundle/`
- **配置文件**: `/opt/xray-bundle/config.json`
- **程序文件**: `/opt/xray-bundle/xray`、`/opt/xray-bundle/cloudflared`

### 服务命令

**Systemd (Debian/Ubuntu/CentOS):**

| 服务 | 说明 |
|------|------|
| `xray-d` | 直连模式 Xray 服务 |
| `xray-t` | 隧道模式 Xray 服务 |
| `cloudflared-t` | Cloudflare Tunnel 服务 |

```bash
systemctl start/stop/restart/status xray-d
systemctl start/stop/restart/status xray-t
systemctl start/stop/restart/status cloudflared-t
```

**OpenRC (Alpine):**

```bash
rc-service xray-d start/stop/restart/status
rc-service xray-t start/stop/restart/status
rc-service cloudflared-t start/stop/restart/status
```

### 命令行服务管理

```bash
# 查看状态
bash main.sh --manage --action status

# 重启服务
bash main.sh --manage --action restart

# 停止服务
bash main.sh --manage --action stop

# 启动服务
bash main.sh --manage --action start
```

## 版本更新

### 交互式更新

```bash
bash main.sh
# 选择 4
```

### 命令行更新

```bash
# 更新所有组件
bash main.sh --update
```

更新功能会自动检测最新版本，并支持：
- 更新 Xray
- 更新 cloudflared
- 全部更新
- 自动备份旧版本
- 更新失败自动回滚

## 二维码显示

### 安装时显示二维码

```bash
bash main.sh --mode direct --port 443 --qr
```

### 服务管理中查看二维码

```bash
bash main.sh
# 选择 3. 服务管理
# 选择 7. 显示配置二维码
```

**注意**: 需要安装 `qrencode` 工具

```bash
# Alpine
apk add qrencode

# Debian/Ubuntu
apt install qrencode

# CentOS
yum install qrencode
```

## 优选域名说明

优选域名是 Cloudflare 优选 IP 服务，用于提升连接速度。

- **默认值**: `cf.tencentapp.cn`
- **用途**: 连接地址使用优选域名，获得更好的速度
- **自定义**: 可以使用自己的优选域名服务

链接格式：
```
vless://UUID@优选域名:443?encryption=none&security=tls&type=ws&host=绑定域名&path=路径&sni=绑定域名
```

## 架构

```
jb/
├── main.sh              # 入口 - 菜单系统、参数解析
├── lib/
│   ├── utils.sh         # 工具函数：日志、验证、下载、端口检测、二维码
│   ├── system.sh        # 系统检测：OS、架构、包管理器
│   ├── service.sh       # 服务管理：systemd / OpenRC
│   └── args.sh          # 命令行参数解析
└── core/
    ├── install_direct.sh   # 直连模式安装
    ├── install_tunnel.sh   # 隧道模式安装
    ├── uninstall.sh        # 卸载
    ├── manage.sh           # 服务管理
    └── update.sh           # 版本更新
```

## 注意事项

1. **防火墙** - 请在云服务商安全组放行所选端口（TCP）
2. **TLS 加密** - 本脚本为无 TLS 模式，建议配合 CDN 或反代使用
3. **Alpine 用户** - 脚本会自动安装兼容包 (`gcompat` 等)
4. **端口占用** - 脚本会自动检测端口占用，提示用户处理
5. **优选域名** - 隧道模式使用优选域名可以获得更好的连接速度

## License

MIT
