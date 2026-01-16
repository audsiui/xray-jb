#!/bin/bash

# 获取当前安装的模式
get_current_mode() {
    if command -v systemctl >/dev/null 2>&1; then
        if [[ -f "/etc/systemd/system/xray-d.service" ]]; then
            echo "direct"
        elif [[ -f "/etc/systemd/system/xray-t.service" ]]; then
            echo "tunnel"
        fi
    elif [[ -d "/etc/init.d" ]]; then
        if [[ -f "/etc/init.d/xray-d" ]]; then
            echo "direct"
        elif [[ -f "/etc/init.d/xray-t" ]]; then
            echo "tunnel"
        fi
    fi
}

# 获取服务状态
get_service_status() {
    local service_name="$1"
    local status=""

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "$service_name"; then
            status="${GREEN}运行中${PLAIN}"
        else
            status="${RED}已停止${PLAIN}"
        fi
        # 添加是否启用信息
        if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
            status="$status (开机自启)"
        else
            status="$status (未启用)"
        fi
    elif [[ -d "/etc/init.d" ]]; then
        if rc-service "$service_name" status 2>/dev/null | grep -q "started"; then
            status="${GREEN}运行中${PLAIN}"
        else
            status="${RED}已停止${PLAIN}"
        fi
        # 检查是否在 default runlevel
        if rc-update show 2>/dev/null | grep -q "$service_name.*default"; then
            status="$status (开机自启)"
        fi
    else
        status="${YELLOW}未知${PLAIN}"
    fi

    echo "$status"
}

# 获取配置信息
get_config_info() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return
    fi

    # 解析 JSON 配置
    local port uuid path
    port=$(grep -oP '"port"\s*:\s*\K[0-9]+' "$CONFIG_FILE" 2>/dev/null)
    uuid=$(grep -oP '"id"\s*:\s*"\K[^"]+' "$CONFIG_FILE" 2>/dev/null)
    path=$(grep -oP '"path"\s*:\s*"\K[^"]+' "$CONFIG_FILE" 2>/dev/null)

    echo "    端口: ${port:-未知}"
    echo "    UUID: ${uuid:-未知}"
    echo "    路径: ${path:-未知}"
}

# 显示详细状态
show_detailed_status() {
    local mode
    mode=$(get_current_mode)

    if [[ -z "$mode" ]]; then
        log_warn "未检测到已安装的服务"
        return 1
    fi

    echo -e "\n${GREEN}=== 服务状态 ===${PLAIN}\n"
    echo "安装模式: ${CYAN}${mode}${PLAIN}"

    if [[ "$mode" == "direct" ]]; then
        echo -e "\nXray 服务 (xray-d):"
        echo -e "  状态: $(get_service_status "xray-d")"
        get_config_info
    elif [[ "$mode" == "tunnel" ]]; then
        echo -e "\nXray 服务 (xray-t):"
        echo -e "  状态: $(get_service_status "xray-t")"
        get_config_info
        echo -e "\nCloudflared 服务 (cloudflared-t):"
        echo -e "  状态: $(get_service_status "cloudflared-t")"
    fi
    echo ""
}

# 执行服务操作
do_service_action() {
    local action="$1"
    local service_name="$2"

    case "$action" in
        start)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl start "$service_name"
            else
                rc-service "$service_name" start
            fi
            ;;
        stop)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl stop "$service_name"
            else
                rc-service "$service_name" stop
            fi
            ;;
        restart)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart "$service_name"
            else
                rc-service "$service_name" restart
            fi
            ;;
        status)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl status "$service_name" --no-pager
            else
                rc-service "$service_name" status
            fi
            ;;
    esac
}

# 根据模式执行操作
run_service_action() {
    local action="$1"
    local mode
    mode=$(get_current_mode)

    if [[ -z "$mode" ]]; then
        log_err "未检测到已安装的服务"
        return 1
    fi

    log_info "执行 ${action} 操作..."

    if [[ "$mode" == "direct" ]]; then
        do_service_action "$action" "xray-d"
    elif [[ "$mode" == "tunnel" ]]; then
        do_service_action "$action" "xray-t"
        do_service_action "$action" "cloudflared-t"
    fi
}

# 交互式选择服务进行操作
interactive_service_action() {
    local action="$1"
    local action_name
    case "$action" in
        start) action_name="启动" ;;
        stop) action_name="停止" ;;
        restart) action_name="重启" ;;
        status) action_name="查看状态" ;;
    esac

    local mode
    mode=$(get_current_mode)

    if [[ -z "$mode" ]]; then
        log_err "未检测到已安装的服务"
        read -p "按回车键返回..."
        return 1
    fi

    if [[ "$mode" == "direct" ]]; then
        log_info "${action_name} Xray 服务..."
        do_service_action "$action" "xray-d"
    elif [[ "$mode" == "tunnel" ]]; then
        echo -e "\n${CYAN}请选择要${action_name}的服务:${PLAIN}"
        echo "  1. Xray 服务"
        echo "  2. Cloudflared 服务"
        echo "  3. 两者都${action_name}"
        read -p "请选择 [1-3]: " choice

        case $choice in
            1) do_service_action "$action" "xray-t" ;;
            2) do_service_action "$action" "cloudflared-t" ;;
            3)
                do_service_action "$action" "xray-t"
                do_service_action "$action" "cloudflared-t"
                ;;
            *) log_err "无效选项" ;;
        esac
    fi

    if [[ "$action" != "status" ]]; then
        log_info "${action_name}完成"
    fi
    read -p "按回车键返回..."
}

# 查看配置链接
show_config_link() {
    local mode
    mode=$(get_current_mode)

    if [[ -z "$mode" ]]; then
        log_err "未检测到已安装的服务"
        return 1
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_err "配置文件不存在"
        return 1
    fi

    # 解析配置
    local port uuid path domain public_ip
    port=$(grep -oP '"port"\s*:\s*\K[0-9]+' "$CONFIG_FILE" 2>/dev/null)
    uuid=$(grep -oP '"id"\s*:\s*"\K[^"]+' "$CONFIG_FILE" 2>/dev/null)
    path=$(grep -oP '"path"\s*:\s*"\K[^"]+' "$CONFIG_FILE" 2>/dev/null)

    if [[ "$mode" == "direct" ]]; then
        public_ip=$(get_public_ip)
        echo "vless://${uuid}@${public_ip}:${port}?encryption=none&security=none&type=ws&path=${path}#Direct_${port}"
    elif [[ "$mode" == "tunnel" ]]; then
        # 从 CF token 文件获取域名比较困难，直接显示配置信息
        log_warn "隧道模式链接需要手动配置域名"
        log_info "UUID: $uuid"
        log_info "端口: $port"
        log_info "路径: $path"
    fi
}

# 服务管理菜单
run_manage_menu() {
    while true; do
        clear
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  服务管理${PLAIN}"
        echo -e "------------------------------------------------"
        echo -e "  1. 查看服务状态"
        echo -e "  2. 启动服务"
        echo -e "  3. 停止服务"
        echo -e "  4. 重启服务"
        echo -e "  5. 查看详细状态"
        echo -e "  6. 查看配置链接"
        echo -e "  7. 显示配置二维码"
        echo -e "  0. 返回主菜单"
        echo -e "------------------------------------------------"

        read -p "请选择 [0-7]: " choice

        case $choice in
            1)
                clear
                show_detailed_status
                read -p "按回车键返回..."
                ;;
            2)
                interactive_service_action "start"
                ;;
            3)
                interactive_service_action "stop"
                ;;
            4)
                interactive_service_action "restart"
                ;;
            5)
                interactive_service_action "status"
                ;;
            6)
                clear
                echo -e "\n${GREEN}=== 配置链接 ===${PLAIN}\n"
                show_config_link
                echo ""
                read -p "按回车键返回..."
                ;;
            7)
                clear
                echo -e "\n${GREEN}=== 配置二维码 ===${PLAIN}\n"
                local link
                link=$(show_config_link)
                if [[ -n "$link" ]]; then
                    show_qr_code "$link"
                fi
                echo ""
                read -p "按回车键返回..."
                ;;
            0)
                return 0
                ;;
            *)
                log_err "无效选项"
                sleep 1
                ;;
        esac
    done
}
