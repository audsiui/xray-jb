# Xray VLESS 工程化部署脚本

轻量级、模块化的 Xray (VLESS + WebSocket) 一键安装脚本。

专为 **Alpine Linux** 优化，同时完美支持 Debian、Ubuntu 和 CentOS。

## 特性

- **模块化架构** - 库文件与核心逻辑分离，易于维护和扩展
- **双模式支持** - 直连模式 + Cloudflare Tunnel 内网穿透
- **智能系统识别** - 自动检测包管理器 (`apk`/`apt`/`yum`) 和服务管理器 (systemd/OpenRC)
- **智能 IP 识别** - 多 API 轮询，支持 IPv4/IPv6 回退和本地路由兜底
- **安全隐蔽** - 自动生成 UUID，动态 WebSocket 路径（4 位随机字符）
- **交互式配置** - 支持自定义端口，带输入验证和错误回滚
- **结果直出** - 安装完成直接输出 `vless://` 链接

## 快速开始

### 一键运行

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
  3. 卸载并清除所有内容
  0. 退出
------------------------------------------------
```

### 安装模式

**直连模式** - 适用于有公网 IP 的服务器
- Xray 监听 `0.0.0.0:端口`
- 输出带公网 IP 的 `vless://` 链接

**Tunnel 模式** - 适用于无公网 IP 或需隐藏真实 IP
- Xray 仅监听 `127.0.0.1:端口`（本地）
- 通过 Cloudflare Tunnel 暴露
- 需提供 CF Tunnel Token

## 服务管理

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

## 架构

```
jb/
├── main.sh              # 入口 - 菜单系统
├── lib/
│   ├── utils.sh         # 工具函数：日志、验证、下载、回滚
│   ├── system.sh        # 系统检测：OS、架构、包管理器
│   └── service.sh       # 服务管理：systemd / OpenRC
└── core/
    ├── install_direct.sh   # 直连模式安装
    ├── install_tunnel.sh   # 隧道模式安装
    └── uninstall.sh        # 卸载
```

## 注意事项

1. **防火墙** - 请在云服务商安全组放行所选端口（TCP）
2. **TLS 加密** - 本脚本为无 TLS 模式，建议配合 CDN 或反代使用
3. **Alpine 用户** - 脚本会自动安装兼容包 (`gcompat` 等)

## License

MIT
