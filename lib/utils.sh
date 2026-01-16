#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 全局变量
WORK_DIR="/opt/xray-bundle"
XRAY_BIN="${WORK_DIR}/xray"
CF_BIN="${WORK_DIR}/cloudflared"
CONFIG_FILE="${WORK_DIR}/config.json"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}"
        exit 1
    fi
}

log_info() { echo -e "${GREEN}[信息] $1${PLAIN}"; }
log_warn() { echo -e "${YELLOW}[警告] $1${PLAIN}"; }
log_err()  { echo -e "${RED}[错误] $1${PLAIN}"; }