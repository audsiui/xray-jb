# xray-jb

模块化的 Xray VLESS 多节点部署管理脚本。支持 REALITY / WS 直连 / Cloudflare Tunnel / XHTTP 四种模式，**同类型节点可添加多个**，一键增删，支持 Alpine（OpenRC）与 Debian/Ubuntu/CentOS（systemd）。

## 特性

- **多节点管理**：每种模式可添加多个节点（不同端口），支持查看链接与删除单个节点
- **`xj` 快捷命令**：首次运行后自动安装，之后随时输入 `xj` 打开管理菜单，不重复下载
- **固定核心版本**：Xray 钉死为 `v26.3.27`（见 `lib/system.sh` 的 `XRAY_VERSION`），不受上游格式变更影响
- **最新配置规范**：REALITY 使用 `target` 字段、sniffing 含 `quic` + `routeOnly`，与官方示例一致
- **最小依赖**：Alpine 仅需 `bash curl ca-certificates`；Xray 为静态链接二进制，无需 glibc 兼容层
- **工程化设计**：模块化脚本、统一 confdir 配置、节点注册表、失败回滚、日志轮转

## 快速开始

```bash
# 一键运行（交互式菜单）
bash <(curl -sL https://raw.githubusercontent.com/audsiui/xray-jb/main/main.sh)
```

按菜单提示添加节点。首次运行完成后：

```bash
xj        # 随时打开管理菜单
```

## 支持的节点类型

| 模式 | 协议栈 | 默认端口 | 说明 |
|------|--------|---------|------|
| direct | VLESS + WS | 8080 | 直连，无需域名 |
| tunnel | VLESS + WS + CF Tunnel | 10086 | 内网穿透，需 Cloudflare Tunnel Token |
| reality | VLESS + REALITY (Vision) | 8443 | 新型直连，无需自备证书 |
| xhttp | VLESS + XHTTP | 8081 | 新型传输层 |

> 同一模式可重复添加多个节点（使用不同端口），也可多种模式共存。

## 命令行（非交互）用法

```bash
bash main.sh -m reality -p 8443                       # 添加 REALITY 节点
bash main.sh -m reality -p 8444                       # 再加一个 REALITY 节点
bash main.sh -m direct -p 8080                        # 添加 WS 直连节点
bash main.sh -m tunnel -p 10086 -d example.com -t <TOKEN>   # 隧道节点
bash main.sh -m xhttp -p 8081                         # XHTTP 节点

bash main.sh -M -a status      # 服务状态
bash main.sh -M -a restart     # 重启服务
bash main.sh -u                # 更新组件
bash main.sh --uninstall       # 卸载全部
```

完整参数见 `bash main.sh -h`。

## 节点管理

主菜单选择 `5. 节点管理`：

- 列出全部节点（类型 / 端口 / UUID）
- 输入序号查看单个节点的分享链接与配置详情
- `l` 查看全部节点分享链接（`vless://` 一键复制）
- `d` 删除节点（自动移除配置并重启 Xray）

## 数据目录结构

```
/opt/xray-bundle/
├── xray                    # Xray 二进制（静态链接）
├── cloudflared             # cloudflared 二进制（隧道模式）
├── confs/                  # 各节点入站配置（多节点统一加载）
│   ├── 10_direct_8080.json
│   ├── 20_reality_8443.json
│   └── ...
├── nodes/                  # 节点注册表（每节点一个 .info 文件）
│   ├── reality_8443.info
│   └── reality_8444.info
├── logs/                   # 运行日志（自动轮转）
└── scripts/                # 脚本持久化副本（供 xj 调用）
```

## 系统要求与依赖

| 系统 | 包管理器 | 安装的依赖 |
|------|---------|-----------|
| Alpine | apk | `bash curl ca-certificates`（unzip 等由 busybox 提供） |
| Debian/Ubuntu | apt | `curl unzip ca-certificates` |
| CentOS | yum | `curl unzip ca-certificates` |

架构支持 `x86_64` 与 `aarch64`。

## 服务管理

**systemd（Debian/Ubuntu/CentOS）**

```bash
systemctl start|stop|restart|status xray            # Xray（所有节点）
systemctl start|stop|restart|status cloudflared-t   # CF Tunnel（隧道模式）
```

**OpenRC（Alpine）**

```bash
rc-service xray start|stop|restart|status
rc-service cloudflared-t start|stop|restart|status
```

## 版本升级策略

- **Xray**：版本钉死为 `v26.3.27`，`xj` 菜单中的"更新"会将 Xray 对齐到该固定版本。升级钉死版本时需同步检查 `core/install_reality.sh` 的密钥解析逻辑（上游曾在 v26 将 `x25519` 公钥行改为 `Password (PublicKey)` 导致过解析失效）
- **cloudflared**：跟随上游 latest

## Docker

提供 `docker/Dockerfile`，基于 alpine 构建镜像运行，Xray 同样钉死 `v26.3.27`（构建参数 `XRAY_VERSION` 可覆盖），详见 `docker/README.md`。

## 注意事项

1. 必须以 root 运行
2. 防火墙需放行所选端口（TCP）；云服务器还需放行安全组
3. 不同节点需使用不同端口避免冲突
4. REALITY 监听非 443 端口时 Xray 会输出 GFW 相关警告，属正常提示
5. 卸载会删除 `/opt/xray-bundle`、所有服务及 `xj` 命令

## License

MIT
