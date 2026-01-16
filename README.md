
# Xray VLESS 一键搭建脚本 (Alpine & Systemd 通用)

这是一个轻量级、高兼容性的 Xray (VLESS + WebSocket) 一键安装脚本。
专为 **Alpine Linux** 优化，同时完美支持 Debian、Ubuntu 和 CentOS。

## ✨ 特性

- **轻量极速**：仅安装必要的 Xray 核心，无臃肿面板。
- **智能 IP 识别**：
  - 优先获取 **IPv4** 公网地址（解决云服务器 NAT 问题）。
  - 自动轮询多个 API 接口，并支持本地路由兜底，获取 IP 成功率极高。
- **高兼容性**：
  - 自动识别系统服务管理器：支持 **Systemd** (Ubuntu/Debian) 和 **OpenRC** (Alpine)。
  - 自动识别包管理器 (`apk`, `apt`, `yum`)。
- **安全隐蔽**：
  - 自动生成 UUID。
  - **Path 动态化**：WebSocket 路径自动截取 UUID 前 4 位（如 `/a1b2`），避免特征扫描。
- **交互式配置**：安装时可自定义端口，也可直接回车使用默认值。
- **结果直出**：运行结束后直接生成 `vless://` 链接，复制即用。

## 🚀 快速开始

### 1. 一键安装
在服务器终端执行以下命令（支持反复运行以更新配置）：

```bash
bash <(curl -sL https://raw.githubusercontent.com/audsiui/xray-jb/main/xray-cless.sh)
```

脚本运行结束后，会直接输出 VLESS 链接，复制到客户端（v2rayN, Shadowrocket 等）导入即可。

### 2. 一键卸载

如果你想彻底清除 Xray 及相关配置：

```bash
bash <(curl -sL https://raw.githubusercontent.com/audsiui/xray-jb/main/uninstall.sh)
```

---

## ⚙️ 详细信息

### 配置文件路径

* **配置文件**: `/usr/local/etc/xray/config.json`
* **程序文件**: `/usr/local/bin/xray`

### 服务管理命令

**Systemd 系统 (Ubuntu / Debian / CentOS):**

```bash
systemctl start xray    # 启动
systemctl stop xray     # 停止
systemctl restart xray  # 重启
systemctl status xray   # 查看状态

```

**Alpine Linux (OpenRC):**

```bash
rc-service xray start
rc-service xray stop
rc-service xray restart
rc-service xray status

```

---

## ⚠️ 注意事项

1. **防火墙设置**：
* 安装脚本支持自定义端口。请务必在云服务商的安全组（防火墙）中放行你设置的端口（TCP）。
* 尤其是 Alpine 用户，如果开启了本地防火墙，请自行放行。


2. **关于加密 (TLS)**：
* 本脚本搭建的是 **VLESS + WS (无 TLS)** 模式。
* **推荐用法**：
* 配合 Cloudflare CDN 使用（将端口改为 80/8080/2052 等 CF 支持的非标准端口）。
* 或者作为 Nginx 前置反代的后端。


* **不推荐**：直接裸连长时间进行大流量传输，可能会被识别。


