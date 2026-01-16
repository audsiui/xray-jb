#!/bin/bash

# 获取当前脚本所在目录
BASE_DIR=$(cd "$(dirname "$0")" && pwd)

# 加载库文件
source "${BASE_DIR}/lib/utils.sh"
source "${BASE_DIR}/lib/system.sh"
source "${BASE_DIR}/lib/service.sh"

# 加载核心模块
source "${BASE_DIR}/core/install_direct.sh"
source "${BASE_DIR}/core/install_tunnel.sh"
source "${BASE_DIR}/core/uninstall.sh"

# 检查 Root
check_root

# 菜单显示
clear
echo -e "------------------------------------------------"
echo -e "${GREEN}  Xray + Tunnel 工程化部署脚本${PLAIN}"
echo -e "------------------------------------------------"
echo -e "  1. 安装 VLESS + WS (直连模式)"
echo -e "  2. 安装 VLESS + WS + CF Tunnel (内网穿透)"
echo -e "  3. 卸载并清除所有内容"
echo -e "  0. 退出"
echo -e "------------------------------------------------"
read -p "请选择 [0-3]: " choice

case $choice in
    1) run_direct_install ;;
    2) run_tunnel_install ;;
    3) run_uninstall ;;
    0) exit 0 ;;
    *) log_err "无效选项" ;;
esac