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
        "main.sh"
        "lib/utils.sh"
        "lib/system.sh"
        "lib/service.sh"
        "lib/args.sh"
        "core/install_direct.sh"
        "core/install_tunnel.sh"
        "core/install_reality.sh"
        "core/install_xhttp.sh"
        "core/uninstall.sh"
        "core/manage.sh"
        "core/update.sh"
    )

    for file in "${FILES[@]}"; do
        mkdir -p "$TMP_DIR/$(dirname "$file")"
        if ! curl -sfL "${REPO_URL}/${file}" -o "$TMP_DIR/$file"; then
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
source "${SCRIPT_DIR}/core/install_reality.sh"
source "${SCRIPT_DIR}/core/install_xhttp.sh"
source "${SCRIPT_DIR}/core/uninstall.sh"
source "${SCRIPT_DIR}/core/manage.sh"
source "${SCRIPT_DIR}/core/update.sh"

# 检查 Root
check_root

# 持久化脚本并创建 xj 快捷命令（首次运行后可直接输入 xj 打开菜单）
ensure_xj_command

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
        reality)
            run_reality_install_non_interactive
            ;;
        xhttp)
            run_xhttp_install_non_interactive
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
    local modes
    modes=$(get_configured_modes)
    echo -e "------------------------------------------------"
    echo -e "${GREEN}  Xray 多节点部署管理脚本${PLAIN}"
    if [[ -n "$modes" ]]; then
        echo -e "  已有节点: ${CYAN}${modes// /}${PLAIN} （详情见节点管理）"
    fi
    echo -e "------------------------------------------------"
    echo -e "  1. 添加 VLESS + WS 直连节点"
    echo -e "  2. 添加 VLESS + WS + CF Tunnel 节点 (内网穿透)"
    echo -e "  3. 添加 VLESS + REALITY 节点"
    echo -e "  4. 添加 VLESS + XHTTP 节点"
    echo -e "  5. 节点管理 (查看链接/删除节点)"
    echo -e "  6. 服务管理"
    echo -e "  7. 更新 Xray/cloudflared 版本"
    echo -e "  8. 卸载并清除所有内容"
    echo -e "  0. 退出"
    echo -e "------------------------------------------------"
}

# 主菜单循环
while true; do
    show_menu
    read -p "请选择 [0-8]: " choice

    case $choice in
        1) run_direct_install; read -p "按回车键继续..." ;;
        2) run_tunnel_install; read -p "按回车键继续..." ;;
        3) run_reality_install; read -p "按回车键继续..." ;;
        4) run_xhttp_install; read -p "按回车键继续..." ;;
        5) run_node_menu ;;
        6) run_manage_menu ;;
        7) run_update; read -p "按回车键继续..." ;;
        8) run_uninstall; read -p "按回车键继续..." ;;
        0) exit 0 ;;
        *) log_err "无效选项"; sleep 1 ;;
    esac
done
