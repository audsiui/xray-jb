#!/bin/bash

# ==========================================
# 交互式 Xray (VLESS+WS) 安装脚本
# 支持：Alpine, Debian, Ubuntu, CentOS
# 输出：直接生成 VLESS 链接
# ==========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 1. 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}" 
   exit 1
fi

# 2. 交互式配置 (输入端口)
echo -e "${GREEN}--------------------------------------${PLAIN}"
read -p "请输入 Xray 运行端口 (默认 8080): " PORT
[[ -z "${PORT}" ]] && PORT=8080

if [[ ! "${PORT}" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}端口必须是数字，请重新运行脚本。${PLAIN}"
    exit 1
fi
echo -e "${GREEN}已选择端口: ${PORT}${PLAIN}"
echo -e "${GREEN}--------------------------------------${PLAIN}"

# 3. 环境检测与依赖安装
OS_TYPE=""
INSTALL_CMD=""

echo -e "${YELLOW}正在检测系统环境...${PLAIN}"
if [ -f /etc/alpine-release ]; then
    OS_TYPE="alpine"
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

$INSTALL_CMD

# 4. 安装 Xray 核心
INSTALL_PATH="/usr/local/bin/xray"
CONFIG_DIR="/usr/local/etc/xray"
mkdir -p ${CONFIG_DIR}

echo -e "${YELLOW}正在获取最新 Xray 版本...${PLAIN}"
LATEST_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
if [[ -z "$LATEST_VERSION" ]] || [[ "$LATEST_VERSION" == "null" ]]; then
    echo -e "${RED}获取版本失败，正在尝试使用备用版本检测...${PLAIN}"
    LATEST_VERSION="v1.8.4" # 备用硬编码版本
fi

echo -e "版本: ${LATEST_VERSION}，开始下载..."
curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/${LATEST_VERSION}/Xray-linux-64.zip"

unzip -o xray.zip -d /tmp/xray_dist > /dev/null 2>&1
mv /tmp/xray_dist/xray ${INSTALL_PATH}
mv /tmp/xray_dist/geosite.dat ${CONFIG_DIR}/
mv /tmp/xray_dist/geoip.dat ${CONFIG_DIR}/
chmod +x ${INSTALL_PATH}
rm -rf xray.zip /tmp/xray_dist

# 5. 生成配置
UUID=$(uuidgen)
WS_PATH="/ws"

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

# 6. 配置服务并启动
echo -e "${YELLOW}正在配置开机自启...${PLAIN}"

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

# 7. 生成分享链接
HOST_IP=$(curl -s ifconfig.me)
# 备注名称
REMARK="Xray_${HOST_IP}_${PORT}"
# VLESS 分享链接格式
LINK="vless://${UUID}@${HOST_IP}:${PORT}?encryption=none&security=none&type=ws&path=%2Fws#${REMARK}"

# 8. 输出结果
echo -e ""
echo -e "${GREEN}==============================================${PLAIN}"
echo -e "${GREEN}          Xray 部署成功 (VLESS + WS)          ${PLAIN}"
echo -e "${GREEN}==============================================${PLAIN}"
echo -e ""
echo -e "${YELLOW}↓↓↓ 复制下面的链接到客户端 (v2rayN/Shadowrocket等) ↓↓↓${PLAIN}"
echo -e ""
echo -e "${CYAN}${LINK}${PLAIN}"
echo -e ""
echo -e "${GREEN}==============================================${PLAIN}"