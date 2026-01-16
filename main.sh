#!/bin/bash

# 远程执行支持：如果模块不存在，自动下载完整目录
REPO_URL="https://raw.githubusercontent.com/audsiui/xray-jb/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查是否是远程执行（模块文件不存在）
if [[ ! -f "${SCRIPT_DIR}/lib/utils.sh" ]]; then
    TMP_DIR="/tmp/xray-jb-$$"
    mkdir -p "$TMP_DIR"

    echo "正在下载脚本文件..."

    # 下载所有必需文件
    FILES=(
        "lib/utils.sh"
        "lib/system.sh"
        "lib/service.sh"
        "lib/args.sh"
        "core/install_direct.sh"
        "core/install_tunnel.sh"
        "core/uninstall.sh"
        "core/manage.sh"
        "core/update.sh"
    )

    for file in "${FILES[@]}"; do
        mkdir -p "$TMP_DIR/$(dirname "$file")"
        if ! curl -sL "${REPO_URL}/${file}" -o "$TMP_DIR/$file"; then
            echo "下载失败: $file"
            rm -rf "$TMP_DIR"
            exit 1
        fi
    done

    SCRIPT_DIR="$TMP_DIR"
fi

# 加载库文件
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/system.sh"
source "${SCRIPT_DIR}/lib/service.sh"
source "${SCRIPT_DIR}/lib/args.sh"

# 加载核心模块
source "${SCRIPT_DIR}/core/install_direct.sh"
source "${SCRIPT_DIR}/core/install_tunnel.sh"
source "${SCRIPT_DIR}/core/uninstall.sh"
source "${SCRIPT_DIR}/core/manage.sh"
source "${SCRIPT_DIR}/core/update.sh"

# 检查 Root
check_root

# 解析命令行参数
parse_args "$@"

# 非交互模式执行
if is_non_interactive; then
    case "$ARG_MODE" in
        direct)
            run_direct_install_non_interactive
            ;;
        tunnel)
            run_tunnel_install_non_interactive
            ;;
        uninstall)
            run_uninstall
            ;;
        manage)
            if [[ -n "$ARG_ACTION" ]]; then
                run_service_action "$ARG_ACTION"
            else
                run_manage_menu
            fi
            ;;
        update)
            run_update
            ;;
    esac
    exit 0
fi

# 交互式菜单
show_menu() {
    clear
    echo -e "------------------------------------------------"
    echo -e "${GREEN}  Xray + Tunnel 工程化部署脚本${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "  1. 安装 VLESS + WS (直连模式)"
    echo -e "  2. 安装 VLESS + WS + CF Tunnel (内网穿透)"
    echo -e "  3. 服务管理"
    echo -e "  4. 更新 Xray/cloudflared 版本"
    echo -e "  5. 卸载并清除所有内容"
    echo -e "  0. 退出"
    echo -e "------------------------------------------------"
}

# 主菜单循环
while true; do
    show_menu
    read -p "请选择 [0-5]: " choice

    case $choice in
        1) run_direct_install; read -p "按回车键继续..." ;;
        2) run_tunnel_install; read -p "按回车键继续..." ;;
        3) run_manage_menu; read -p "按回车键继续..." ;;
        4) run_update; read -p "按回车键继续..." ;;
        5) run_uninstall; read -p "按回车键继续..." ;;
        0) exit 0 ;;
        *) log_err "无效选项"; sleep 1 ;;
    esac
done
