#!/bin/bash

# 获取已配置的入站模式列表（基于节点注册表，支持同模式多节点）
get_configured_modes() {
    local modes="" f mode
    for f in $(list_node_files); do
        mode=$(grep "^MODE=" "$f" 2>/dev/null | cut -d'=' -f2)
        if [[ -n "$mode" && " $modes " != *" $mode "* ]]; then
            modes="${modes}${mode} "
        fi
    done
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

# 查看配置链接（遍历节点注册表，展示全部节点）
show_config_link() {
    local found_config=false f mode

    for f in $(list_node_files); do
        mode=$(grep "^MODE=" "$f" 2>/dev/null | cut -d'=' -f2)
        case "$mode" in
            direct)  show_direct_config "$f"; found_config=true ;;
            tunnel)  show_tunnel_config "$f"; found_config=true ;;
            reality) show_reality_config "$f"; found_config=true ;;
            xhttp)   show_xhttp_config "$f"; found_config=true ;;
        esac
    done

    if [[ "$found_config" == "false" ]]; then
        log_err "未检测到任何节点，请先添加节点"
        return 1
    fi
}

# 显示直连节点配置（参数: 节点信息文件）
show_direct_config() {
    local info_file="$1"
    if [[ -f "$info_file" ]]; then
        local port uuid path public_ip
        port=$(grep "^PORT=" "$info_file" | cut -d'=' -f2)
        uuid=$(grep "^UUID=" "$info_file" | cut -d'=' -f2)
        path=$(grep "^PATH=" "$info_file" | cut -d'=' -f2)

        if [[ -n "$uuid" && -n "$port" && -n "$path" ]]; then
            public_ip=$(get_public_ip)
            local link="vless://${uuid}@${public_ip}:${port}?encryption=none&security=none&type=ws&path=${path}#Direct_${port}"
            echo -e "\n${GREEN}=== 直连节点 [端口 ${port}] ===${PLAIN}"
            echo -e "${CYAN}${link}${PLAIN}"
        fi
    fi
}

# 显示隧道节点配置（参数: 节点信息文件）
show_tunnel_config() {
    local info_file="$1"
    if [[ -f "$info_file" ]]; then
        local port uuid path domain opt_domain
        port=$(grep "^PORT=" "$info_file" | cut -d'=' -f2)
        uuid=$(grep "^UUID=" "$info_file" | cut -d'=' -f2)
        path=$(grep "^PATH=" "$info_file" | cut -d'=' -f2)
        domain=$(grep "^DOMAIN=" "$info_file" | cut -d'=' -f2)
        opt_domain=$(grep "^OPT_DOMAIN=" "$info_file" | cut -d'=' -f2)

        if [[ -n "$domain" && -n "$opt_domain" && -n "$uuid" && -n "$path" ]]; then
            local link="vless://${uuid}@${opt_domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=${path}&sni=${domain}#Tunnel_${domain}_${port}"
            echo -e "\n${GREEN}=== 隧道节点 [端口 ${port}] ===${PLAIN}"
            echo -e "${CYAN}${link}${PLAIN}"
        fi
    fi
}

# 显示 REALITY 节点配置（参数: 节点信息文件）
show_reality_config() {
    local info_file="$1"

    if [[ -f "$info_file" ]]; then
        local port uuid domain public_key short_id public_ip private_key
        port=$(grep "^PORT=" "$info_file" 2>/dev/null | cut -d'=' -f2)
        uuid=$(grep "^UUID=" "$info_file" 2>/dev/null | cut -d'=' -f2)
        domain=$(grep "^DOMAIN=" "$info_file" 2>/dev/null | cut -d'=' -f2)
        public_key=$(grep "^PUBLIC_KEY=" "$info_file" 2>/dev/null | cut -d'=' -f2)
        short_id=$(grep "^SHORT_ID=" "$info_file" 2>/dev/null | cut -d'=' -f2)

        if [[ -n "$uuid" && -n "$port" && -n "$public_key" && -n "$short_id" ]]; then
            public_ip=$(get_public_ip)
            # REALITY 链接格式
            local link="vless://${uuid}@${public_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${domain}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#REALITY_${port}"

            echo -e "\n${GREEN}=== REALITY 节点 [端口 ${port}] ===${PLAIN}"
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

# 显示 XHTTP 节点配置（参数: 节点信息文件）
show_xhttp_config() {
    local info_file="$1"

    if [[ -f "$info_file" ]]; then
        local port uuid path public_ip
        port=$(grep "^PORT=" "$info_file" 2>/dev/null | cut -d'=' -f2)
        uuid=$(grep "^UUID=" "$info_file" 2>/dev/null | cut -d'=' -f2)
        path=$(grep "^PATH=" "$info_file" 2>/dev/null | cut -d'=' -f2)

        if [[ -n "$uuid" && -n "$port" && -n "$path" ]]; then
            public_ip=$(get_public_ip)
            local link="vless://${uuid}@${public_ip}:${port}?encryption=none&security=none&type=xhttp&path=${path}#XHTTP_${port}"

            echo -e "\n${GREEN}=== XHTTP 节点 [端口 ${port}] ===${PLAIN}"
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

# 显示单个节点详情（参数: 节点信息文件）
show_single_node() {
    local info_file="$1"
    local mode
    mode=$(grep "^MODE=" "$info_file" 2>/dev/null | cut -d'=' -f2)
    case "$mode" in
        direct)  show_direct_config "$info_file" ;;
        tunnel)  show_tunnel_config "$info_file" ;;
        reality) show_reality_config "$info_file" ;;
        xhttp)   show_xhttp_config "$info_file" ;;
        *) log_err "未知节点类型: ${mode}" ;;
    esac
}

# 删除节点（移除配置与注册信息，重启服务）
delete_node_by_file() {
    local info_file="$1"
    local mode port
    mode=$(grep "^MODE=" "$info_file" 2>/dev/null | cut -d'=' -f2)
    port=$(grep "^PORT=" "$info_file" 2>/dev/null | cut -d'=' -f2)

    if [[ -z "$mode" || -z "$port" ]]; then
        log_err "节点信息文件损坏: ${info_file}"
        return 1
    fi

    echo ""
    echo -e "将删除节点: ${YELLOW}[${mode}] 端口 ${port}${PLAIN}"
    read -p "确认删除？[y/N]: " confirm
    confirm=$(trim "$confirm")
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "已取消删除"
        return 0
    fi

    remove_inbound_config "$mode" "$port"
    remove_node_info "$mode" "$port"

    # 重启 Xray 应用配置
    if service_exists "xray"; then
        do_service_action "restart" "xray"
        if verify_service_running "xray"; then
            log_info "节点已删除，Xray 重启成功"
        fi
    else
        log_warn "Xray 服务未安装，仅清理了本地配置"
    fi

    # 删除最后一个隧道节点时提示 cloudflared 状态
    if [[ "$mode" == "tunnel" ]] && [[ -z "$(list_node_files tunnel)" ]]; then
        log_warn "已无隧道节点；cloudflared 服务仍在运行，如需彻底清理请使用卸载功能"
    fi
}

# 节点管理菜单（查看/删除节点，支持同模式多节点）
run_node_menu() {
    while true; do
        clear
        echo -e "------------------------------------------------"
        echo -e "${GREEN}  节点管理${PLAIN}"
        echo -e "------------------------------------------------"

        local files=()
        local f
        while IFS= read -r f; do
            [[ -n "$f" ]] && files+=("$f")
        done < <(list_node_files)

        if [[ ${#files[@]} -eq 0 ]]; then
            log_warn "当前没有已添加的节点，请先在主菜单添加"
            echo ""
            read -p "按回车键返回..."
            return 0
        fi

        echo -e "  共有 ${GREEN}${#files[@]}${PLAIN} 个节点:\n"
        local i=1 mode port uuid
        for f in "${files[@]}"; do
            mode=$(grep "^MODE=" "$f" 2>/dev/null | cut -d'=' -f2)
            port=$(grep "^PORT=" "$f" 2>/dev/null | cut -d'=' -f2)
            uuid=$(grep "^UUID=" "$f" 2>/dev/null | cut -d'=' -f2)
            printf "  %2d. ${CYAN}%-9s${PLAIN} 端口 %-6s UUID: %s...\n" "$i" "[${mode}]" "${port}" "${uuid:0:13}"
            ((i++))
        done
        echo ""
        echo -e "  输入序号查看节点详情"
        echo -e "  l. 查看全部节点链接"
        echo -e "  d. 删除节点"
        echo -e "  0. 返回主菜单"
        echo -e "------------------------------------------------"

        read -p "请选择 [1-${#files[@]}/l/d/0]: " choice

        case "$choice" in
            0)
                return 0
                ;;
            l|L)
                clear
                echo -e "\n${GREEN}=== 全部节点链接 ===${PLAIN}\n"
                show_config_link
                echo ""
                read -p "按回车键返回..."
                ;;
            d|D)
                read -p "请输入要删除的节点序号 [1-${#files[@]}]: " idx
                if [[ ! "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#files[@]} )); then
                    log_err "无效序号"
                    sleep 1
                    continue
                fi
                delete_node_by_file "${files[$((idx - 1))]}"
                read -p "按回车键返回..."
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#files[@]} )); then
                    clear
                    show_single_node "${files[$((choice - 1))]}"
                    echo ""
                    read -p "按回车键返回..."
                else
                    log_err "无效选项"
                    sleep 1
                fi
                ;;
        esac
    done
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
        echo -e "  6. 节点管理（查看/删除节点）"
        echo -e "  7. 查看全部节点链接"
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
                run_node_menu
                ;;
            7)
                clear
                echo -e "\n${GREEN}=== 全部节点链接 ===${PLAIN}\n"
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
