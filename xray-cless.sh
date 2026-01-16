#!/bin/bash

# ==========================================
# 交互式 Xray (VLESS+WS) 极速安装脚本
# 特性：
# 1. 优先获取 IPv4 (多接口轮询 + 超时控制)
# 2. 路径 Path 自动设置为 UUID 的前 4 位
# 3. 兼容 Alpine (OpenRC) 与主流 Systemd 系统
# 4. 运行结束直接输出分享链接
# ==========================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 1. 权限检查 ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}" 
   exit 1
fi

# --- 2. 交互式配置端口 ---
echo -e "${GREEN}--------------------------------------${PLAIN}"
read -p "请输入 Xray 运行端口 (留空默认 8080): " PORT
[[ -z "${PORT}" ]] && PORT=8080

if [[ ! "${PORT}" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}错误: 端口必须是数字。${PLAIN}"
    exit 1
fi
echo -e "${GREEN}已选择端口: ${PORT}${PLAIN}"
echo -e "${GREEN}--------------------------------------${PLAIN}"

# --- 3. 环境检测与依赖安装 ---
OS_TYPE=""
INSTALL_CMD=""

echo -e "${YELLOW}正在检测系统环境...${PLAIN}"
if [ -f /etc/alpine-release ]; then
    OS_TYPE="alpine"
    # Alpine 需要 bash, curl, coreutils(uuidgen), jq
    INSTALL_CMD="apk add --no-cache curl unzip jq util-linux bash ca-certificates"
elif [ -f /etc/debian_version ]; then
    OS_TYPE="debian"
    INSTALL_CMD="apt update && apt install -y curl unzip jq uuid-runtime ca-certificates"
elif [ -f /etc/redhat-release ]; then
    OS_TYPE="centos"
    INSTALL_CMD="yum install -y curl unzip jq ca-certificates"
else
    echo -e "${RED}不支持的系统，脚本退出。${PLAIN}"
    exit 1
fi

echo -e "${YELLOW}正在安装必要依赖...${PLAIN}"
eval $INSTALL_CMD > /dev/null 2>&1

# --- 4. 安装 Xray 核心 ---
INSTALL_PATH="/usr/local/bin/xray"
CONFIG_DIR="/usr/local/etc/xray"
mkdir -p ${CONFIG_DIR}

echo -e "${YELLOW}正在获取最新 Xray 版本...${PLAIN}"
# 获取最新版本 Tag，如果获取失败则使用固定版本兜底
LATEST_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
if [[ -z "$LATEST_VERSION" ]] || [[ "$LATEST_VERSION" == "null" ]]; then
    LATEST_VERSION="v1.8.4"
    echo -e "${RED}版本获取失败，使用兜底版本: ${LATEST_VERSION}${PLAIN}"
else
    echo -e "最新版本: ${LATEST_VERSION}"
fi

# 下载
DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${LATEST_VERSION}/Xray-linux-64.zip"
curl -L -o xray.zip "$DOWNLOAD_URL"

# 解压与安装
unzip -o xray.zip -d /tmp/xray_dist > /dev/null 2>&1
mv /tmp/xray_dist/xray ${INSTALL_PATH}
mv /tmp/xray_dist/geosite.dat ${CONFIG_DIR}/
mv /tmp/xray_dist/geoip.dat ${CONFIG_DIR}/
chmod +x ${INSTALL_PATH}
rm -rf xray.zip /tmp/xray_dist

# --- 5. 生成配置文件 ---
UUID=$(uuidgen)
# 截取 UUID 前 4 位作为 Path (如 /a1b2)
WS_PATH="/${UUID:0:4}"

cat > ${CONFIG_DIR}/config.json << EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}", "level": 0 } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "${WS_PATH}" }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
EOF

# --- 6. 配置服务并启动 ---
echo -e "${YELLOW}正在配置系统服务...${PLAIN}"

if [[ "$OS_TYPE" == "alpine" ]]; then
    # Alpine OpenRC 配置
    cat > /etc/init.d/xray << EOF
#!/sbin/openrc-run
name="xray"
description="Xray Service"
command="${INSTALL_PATH}"
command_args="run -c ${CONFIG_DIR}/config.json"
command_background=true
pidfile="/run/xray.pid"
depend() {
    need net
    after firewall
}
EOF
    chmod +x /etc/init.d/xray
    rc-update add xray default
    rc-service xray restart > /dev/null 2>&1
else
    # Systemd 配置
    cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target
[Service]
ExecStart=${INSTALL_PATH} run -c ${CONFIG_DIR}/config.json
Restart=on-failure
User=root
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable xray > /dev/null 2>&1
    systemctl restart xray
fi

# --- 7. 获取服务器 IP (健壮版) ---
echo -e "${YELLOW}正在获取服务器公网 IP...${PLAIN}"

get_public_ip() {
    # 1. 优先尝试 IPv4 API 列表
    ipv4_apis=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://ipv4.icanhazip.com"
        "http://whatismyip.akamai.com"
    )
    
    local ip=""
    for api in "${ipv4_apis[@]}"; do
        # 超时时间: 连接2秒，总时间3秒
        ip=$(curl -s4m3 --connect-timeout 2 "$api" | tr -d '\n' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')
        if [[ ! -z "$ip" ]]; then
            echo "$ip"
            return
        fi
    done

    # 2. IPv4 失败，尝试 IPv6 API 列表
    if [[ -z "$ip" ]]; then
        ipv6_apis=(
            "https://api64.ipify.org"
            "https://ipv6.icanhazip.com"
        )
        for api in "${ipv6_apis[@]}"; do
            ip=$(curl -s6m3 --connect-timeout 2 "$api" | tr -d '\n')
            if [[ ! -z "$ip" ]]; then
                echo "$ip"
                return
            fi
        done
    fi

    # 3. 绝境兜底：使用 ip route 获取默认出口 IP
    if [[ -z "$ip" ]]; then
        ip=$(ip -4 route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+')
    fi

    echo "$ip"
}

HOST_IP=$(get_public_ip)

if [[ -z "$HOST_IP" ]]; then
    HOST_IP="127.0.0.1"
    echo -e "${RED}警告: 无法获取公网 IP，链接中将使用 127.0.0.1${PLAIN}"
fi

# --- 8. 生成并输出链接 ---
REMARK="Xray_${HOST_IP}_${PORT}"
# 构造链接
LINK="vless://${UUID}@${HOST_IP}:${PORT}?encryption=none&security=none&type=ws&path=${WS_PATH}#${REMARK}"

echo -e ""
echo -e "${GREEN}==============================================${PLAIN}"
echo -e "${GREEN}          Xray 部署成功 (VLESS + WS)          ${PLAIN}"
echo -e "${GREEN}==============================================${PLAIN}"
echo -e "   - IP 地址: ${HOST_IP}"
echo -e "   - 端口   : ${PORT}"
echo -e "   - UUID   : ${UUID}"
echo -e "   - Path   : ${WS_PATH}"
echo -e "${GREEN}----------------------------------------------${PLAIN}"
echo -e "${YELLOW}↓↓↓ 复制下面的链接到客户端 (v2rayN / Shadowrocket) ↓↓↓${PLAIN}"
echo -e ""
echo -e "${CYAN}${LINK}${PLAIN}"
echo -e ""
echo -e "${GREEN}==============================================${PLAIN}"