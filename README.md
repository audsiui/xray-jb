# Xray VLESS 部署脚本

![Shell](https://img.shields.io/badge/shell-bash-blue)
![License](https://img.shields.io/github/license/audsiui/xray-jb)
![Version](https://img.shields.io/github/v/release/audsiui/xray-jb)
![Stars](https://img.shields.io/github/stars/audsiui/xray-jb)

Xray (VLESS + WebSocket) 一键安装，支持 Alpine/Debian/Ubuntu/CentOS。

## 快速开始

```bash
bash <(curl -sL https://raw.githubusercontent.com/audsiui/xray-jb/main/main.sh)
```

- [Docker 部署](docker/README.md) - 容器化平台
- [在线配置生成器](https://audsiui.github.io/xray-jb/generator.html)

## 安装模式

| 模式 | 说明 |
|------|------|
| 直连 | 适合有公网 IP，监听 `0.0.0.0:端口` |
| Tunnel | 通过 Cloudflare Tunnel 内网穿透，监听 `127.0.0.1:端口` |

```bash
# 直连模式
bash main.sh --mode direct --port 443

# 隧道模式
bash main.sh --mode tunnel --domain example.com --token xxxx
```

## 命令行参数

| 参数 | 说明 |
|------|------|
| `-m, --mode` | `direct`(直连) / `tunnel`(隧道) / `uninstall`(卸载) / `manage`(管理) / `update`(更新) |
| `-p, --port` | 端口 (直连默认 8080, 隧道默认 10086) |
| `-d, --domain` | 域名 (tunnel 模式必需) |
| `-t, --token` | Cloudflare Tunnel Token (tunnel 模式必需) |
| `--opt-domain` | 优选域名 (默认 `cf.tencentapp.cn`) |
| `-a, --action` | 服务操作: `start`/`stop`/`restart`/`status` |
| `-q, --quiet` | 静默模式 |
| `-h, --help` | 帮助 |

## 服务管理

```bash
# 交互式菜单
bash main.sh  # 选择 3

# 命令行
bash main.sh --manage --action status
bash main.sh --manage --action restart
```

**手动管理服务:**

Systemd: `systemctl start/stop/restart/status xray-d`
OpenRC: `rc-service xray-d start/stop/restart/status`

服务名: `xray-d`(直连) / `xray-t`(隧道) / `cloudflared-t`(CF Tunnel)

## 日志

**位置**: `/opt/xray-bundle/logs/`

```bash
# 实时查看
tail -f /opt/xray-bundle/logs/xray-d.log

# systemd 额外日志
journalctl -u xray-d -f
```

日志自动轮转，保留 3 个备份。

## 文件路径

```
/opt/xray-bundle/
├── config.json       # 配置
├── xray             # Xray 程序
├── cloudflared      # CF Tunnel 程序
└── logs/            # 日志目录
```

## 优选域名

隧道模式默认使用 `cf.tencentapp.cn`，可通过 `--opt-domain` 自定义。

## 注意事项

1. 防火墙需放行所选端口 (TCP)
2. 本脚本为无 TLS 模式，建议配合 CDN 使用
3. Alpine 会自动安装兼容包 (`gcompat` 等)

## License

MIT
