#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
PLAIN='\033[0m'

echo -e "${RED}正在停止 Xray 服务...${PLAIN}"

# 1. 停止服务并移除开机自启
if [ -f /etc/alpine-release ]; then
    # Alpine (OpenRC)
    if [ -f /etc/init.d/xray ]; then
        rc-service xray stop
        rc-update del xray
        rm -f /etc/init.d/xray
    fi
else
    # Systemd (Debian/CentOS/Ubuntu)
    systemctl stop xray
    systemctl disable xray
    rm -f /etc/systemd/system/xray.service
    systemctl daemon-reload
fi

# 2. 删除文件
echo -e "${RED}正在删除文件...${PLAIN}"
rm -rf /usr/local/bin/xray      # 删除主程序
rm -rf /usr/local/etc/xray      # 删除配置文件和证书
rm -f /var/run/xray.pid         # 删除 PID 文件

echo -e "${GREEN}Xray 已彻底卸载！${PLAIN}"