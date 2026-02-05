#!/bin/bash

# 获取已配置的入站模式列表
get_configured_modes() {
    local modes=""
    [[ -f "${WORK_DIR}/.direct_info" ]] && modes="${modes}direct "
    [[ -f "${WORK_DIR}/.domain_info" ]] && modes="${modes}tunnel "
    [[ -f "${WORK_DIR}/.reality_keys" ]] && modes="${modes}reality "
    [[ -f "${WORK_DIR}/.xhttp_info" ]] && modes="${modes}xhttp "
    echo "$modes"
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

# 获取配置信息（根据服务名获取对应配置）
get_config_info() {
    local service_name="$1"
    local config_file=""

    case "$service_name" in
        xray-d) config_file="${WORK_DIR}/config-direct.json" ;;
        xray-t) config_file="${WORK_DIR}/config-tunnel.json" ;;
        xray-r) config_file="${WORK_DIR}/config-reality.json" ;;
        *) return ;;
    esac

    if [[ ! -f "$config_file" ]]; then
        return
    fi

    # 解析 JSON 配置（使用 sed 而非 grep -P 以兼容更多系统）
    local port uuid path

    # 提取 port: "port": 数字,
    port=$(sed -nE 's/.*"port"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$config_file" | head -1)

    # 提取 uuid: "id": "uuid-string"
    uuid=$(sed -nE 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$config_file" | head -1)

    # 提取 path: "path": "/path-string" (仅 WS 模式有)
    path=$(sed -nE 's/.*"path"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$config_file" | head -1)

    echo "    端口: ${port:-未知}"
    echo "    UUID: ${uuid:-未知}"
    [[ -n "$path" ]] && echo "    路径: ${path}"
}

# 显示详细状态（单服务多模式）
show_detailed_status() {
    echo -e "\n${GREEN}=== 服务状态 ===${PLAIN}\n"

    local modes
    modes=$(get_configured_modes)

    if [[ -z "$modes" ]] && ! has_xray_service; then
        log_warn "未检测到已安装的服务"
        return 1
    fi

    # 显示 Xray 主服务状态
    if has_xray_service; then
        echo -e "Xray 服务:"
        echo -e "  状态: $(get_service_status "xray")"
        echo ""
    fi

    # 显示已配置的入站模式
    if [[ -n "$modes" ]]; then
        echo -e "已配置入站:"
        [[ "$modes" == *"direct"* ]] && echo "  • 直连模式 (VLESS+WS)"
        [[ "$modes" == *"tunnel"* ]] && echo "  • 隧道模式 (VLESS+WS+CF)"
        [[ "$modes" == *"reality"* ]] && echo "  • REALITY 模式 (VLESS+REALITY)"
        [[ "$modes" == *"xhttp"* ]] && echo "  • XHTTP 模式 (VLESS+XHTTP)"
        echo ""
    fi

    # 显示 Cloudflared 状态
    if command -v systemctl >/dev/null 2>&1; then
        [[ -f "/etc/systemd/system/cloudflared-t.service" ]] && echo -e "Cloudflared: $(get_service_status "cloudflared-t")"
    elif [[ -d "/etc/init.d" ]]; then
        [[ -f "/etc/init.d/cloudflared-t" ]] && echo -e "Cloudflared: $(get_service_status "cloudflared-t")"
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

    if ! has_xray_service && [[ ! -f "/etc/systemd/system/cloudflared-t.service" ]] && [[ ! -f "/etc/init.d/cloudflared-t" ]]; then
        log_err "未检测到已安装的服务"
        return 1
    fi

    log_info "执行 ${action} 操作..."

    # 操作 Xray 主服务
    if has_xray_service; then
        do_service_action "$action" "xray"
    fi

    # 操作 Cloudflared 服务
    if command -v systemctl >/dev/null 2>&1; then
        [[ -f "/etc/systemd/system/cloudflared-t.service" ]] && do_service_action "$action" "cloudflared-t"
    elif [[ -d "/etc/init.d" ]]; then
        [[ -f "/etc/init.d/cloudflared-t" ]] && do_service_action "$action" "cloudflared-t"
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

    # 检测已安装的服务
    local has_xray=false
    local has_cf=false
    has_xray_service && has_xray=true
    if command -v systemctl >/dev/null 2>&1; then
        [[ -f "/etc/systemd/system/cloudflared-t.service" ]] && has_cf=true
    elif [[ -d "/etc/init.d" ]]; then
        [[ -f "/etc/init.d/cloudflared-t" ]] && has_cf=true
    fi

    if [[ "$has_xray" == "false" && "$has_cf" == "false" ]]; then
        log_err "未检测到已安装的服务"
        read -p "按回车键返回..."
        return 1
    fi

    # 如果只有一个服务，直接执行
    if [[ "$has_xray" == "true" && "$has_cf" == "false" ]]; then
        log_info "${action_name} Xray 服务..."
        do_service_action "$action" "xray"
        if [[ "$action" != "status" ]]; then
            log_info "${action_name}完成"
        fi
        read -p "按回车键返回..."
        return 0
    elif [[ "$has_xray" == "false" && "$has_cf" == "true" ]]; then
        log_info "${action_name} Cloudflared 服务..."
        do_service_action "$action" "cloudflared-t"
        if [[ "$action" != "status" ]]; then
            log_info "${action_name}完成"
        fi
        read -p "按回车键返回..."
        return 0
    fi

    # 两个服务都有，显示选择菜单
    echo -e "\n${CYAN}请选择要${action_name}的服务:${PLAIN}"
    echo "  1. Xray 服务（所有入站）"
    echo "  2. Cloudflared 服务"
    echo "  3. 两者都${action_name}"
    read -p "请选择 [1-3]: " choice

    case $choice in
        1) do_service_action "$action" "xray" ;;
        2) do_service_action "$action" "cloudflared-t" ;;
        3)
            do_service_action "$action" "xray"
            do_service_action "$action" "cloudflared-t"
            ;;
        *) log_err "无效选项" ;;
    esac

    if [[ "$action" != "status" ]]; then
        log_info "${action_name}完成"
    fi
    read -p "按回车键返回..."
}

# 查看配置链接（支持多模式显示）
show_config_link() {
    local found_config=false

    # 检测并显示所有已安装模式的配置
    [[ -f "${WORK_DIR}/.direct_info" ]] && { show_direct_config; found_config=true; }
    [[ -f "${WORK_DIR}/.domain_info" ]] && { show_tunnel_config; found_config=true; }
    [[ -f "${WORK_DIR}/.reality_keys" ]] && { show_reality_config; found_config=true; }
    [[ -f "${WORK_DIR}/.xhttp_info" ]] && { show_xhttp_config; found_config=true; }

    if [[ "$found_config" == "false" ]]; then
        log_err "未检测到已安装的服务"
        return 1
    fi
}

# 显示直连模式配置
show_direct_config() {
    local direct_config="${WORK_DIR}/config-direct.json"
    if [[ -f "$direct_config" ]]; then
        local port uuid path public_ip
        port=$(sed -nE 's/.*"port"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$direct_config" | head -1)
        uuid=$(sed -nE 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$direct_config" | head -1)
        path=$(sed -nE 's/.*"path"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$direct_config" | head -1)

        if [[ -n "$uuid" && -n "$port" && -n "$path" ]]; then
            public_ip=$(get_public_ip)
            local link="vless://${uuid}@${public_ip}:${port}?encryption=none&security=none&type=ws&path=${path}#Direct_${port}"
            echo -e "\n${GREEN}=== 直连模式配置 ===${PLAIN}"
            echo -e "${CYAN}${link}${PLAIN}"
        fi
    fi
}

# 显示隧道模式配置
show_tunnel_config() {
    local tunnel_config="${WORK_DIR}/config-tunnel.json"
    if [[ -f "$tunnel_config" ]]; then
        local port uuid path
        port=$(sed -nE 's/.*"port"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$tunnel_config" | head -1)
        uuid=$(sed -nE 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$tunnel_config" | head -1)
        path=$(sed -nE 's/.*"path"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$tunnel_config" | head -1)

        local domain_info_file="${WORK_DIR}/.domain_info"
        local domain opt_domain

        if [[ -f "$domain_info_file" ]]; then
            domain=$(grep "^DOMAIN=" "$domain_info_file" 2>/dev/null | cut -d'=' -f2)
            opt_domain=$(grep "^OPT_DOMAIN=" "$domain_info_file" 2>/dev/null | cut -d'=' -f2)
        fi

        if [[ -n "$domain" && -n "$opt_domain" && -n "$uuid" && -n "$path" ]]; then
            local link="vless://${uuid}@${opt_domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=${path}&sni=${domain}#Tunnel_${domain}"
            echo -e "\n${GREEN}=== 隧道模式配置 ===${PLAIN}"
            echo -e "${CYAN}${link}${PLAIN}"
        fi
    fi
}

# 显示 REALITY 模式配置
show_reality_config() {
    local keys_file="${WORK_DIR}/.reality_keys"

    if [[ -f "$keys_file" ]]; then
        local port uuid domain public_key short_id public_ip
        port=$(grep "^PORT=" "$keys_file" 2>/dev/null | cut -d'=' -f2)
        uuid=$(grep "^UUID=" "$keys_file" 2>/dev/null | cut -d'=' -f2)
        domain=$(grep "^DOMAIN=" "$keys_file" 2>/dev/null | cut -d'=' -f2)
        public_key=$(grep "^PUBLIC_KEY=" "$keys_file" 2>/dev/null | cut -d'=' -f2)
        short_id=$(grep "^SHORT_ID=" "$keys_file" 2>/dev/null | cut -d'=' -f2)

        if [[ -n "$uuid" && -n "$port" && -n "$public_key" && -n "$short_id" ]]; then
            public_ip=$(get_public_ip)
            # REALITY 链接格式
            local link="vless://${uuid}@${public_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${domain}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#REALITY_${port}"

            echo -e "\n${GREEN}=== REALITY 模式配置 ===${PLAIN}"
            echo -e "${CYAN}${link}${PLAIN}"
            echo ""
            echo -e "${GREEN}配置详情:${PLAIN}"
            echo -e "  地址: ${CYAN}${public_ip}${PLAIN}"
            echo -e "  端口: ${CYAN}${port}${PLAIN}"
            echo -e "  UUID: ${CYAN}${uuid}${PLAIN}"
            echo -e "  传输协议: ${CYAN}tcp${PLAIN}"
            echo -e "  安全协议: ${CYAN}reality${PLAIN}"
            echo -e "  Flow: ${CYAN}xtls-rprx-vision${PLAIN}"
            echo -e "  SNI: ${CYAN}${domain}${PLAIN}"
            echo -e "  公钥 (PublicKey): ${CYAN}${public_key}${PLAIN}"
            echo -e "  ShortId: ${CYAN}${short_id}${PLAIN}"
            echo -e "  指纹 (Fingerprint): ${CYAN}chrome${PLAIN}"
        fi
    fi
}

# 显示 XHTTP 模式配置
show_xhttp_config() {
    local xhttp_info="${WORK_DIR}/.xhttp_info"

    if [[ -f "$xhttp_info" ]]; then
        local port uuid path public_ip
        port=$(grep "^PORT=" "$xhttp_info" 2>/dev/null | cut -d'=' -f2)
        uuid=$(grep "^UUID=" "$xhttp_info" 2>/dev/null | cut -d'=' -f2)
        path=$(grep "^PATH=" "$xhttp_info" 2>/dev/null | cut -d'=' -f2)

        if [[ -n "$uuid" && -n "$port" && -n "$path" ]]; then
            public_ip=$(get_public_ip)
            local link="vless://${uuid}@${public_ip}:${port}?encryption=none&security=none&type=xhttp&path=${path}#XHTTP_${port}"

            echo -e "\n${GREEN}=== XHTTP 模式配置 ===${PLAIN}"
            echo -e "${CYAN}${link}${PLAIN}"
            echo ""
            echo -e "${GREEN}配置详情:${PLAIN}"
            echo -e "  地址: ${CYAN}${public_ip}${PLAIN}"
            echo -e "  端口: ${CYAN}${port}${PLAIN}"
            echo -e "  UUID: ${CYAN}${uuid}${PLAIN}"
            echo -e "  传输协议: ${CYAN}xhttp${PLAIN}"
            echo -e "  路径: ${CYAN}${path}${PLAIN}"
        fi
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
        echo -e "  0. 返回主菜单"
        echo -e "------------------------------------------------"

        read -p "请选择 [0-6]: " choice

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
