#!/bin/bash

# 非交互式安装入口
run_direct_install_non_interactive() {
    # 检测是否已安装
    if ! check_existing_install "direct"; then
        exit 1
    fi

    # 使用命令行参数或默认值
    PORT="${ARG_PORT:-8080}"

    # 检查端口是否被占用（非交互模式下直接使用）
    if ! check_port_available "$PORT"; then
        local process_info
        process_info=$(get_port_process "$PORT")
        log_warn "端口 ${PORT} 已被占用 (${process_info})"
        log_warn "非交互模式将强制使用此端口"
    fi

    _do_direct_install
}

# 交互式安装入口
run_direct_install() {
    # 检测是否已安装
    if ! check_existing_install "direct"; then
        return 1
    fi

    _do_direct_install
}

# 实际安装逻辑
_do_direct_install() {

    # 1. 基础安装
    check_sys
    get_arch
    mkdir -p ${WORK_DIR}
    init_log_dir

    # 2. 检查是否需要下载 Xray
    if [[ -f "${XRAY_BIN}" ]] && "${XRAY_BIN}" version >/dev/null 2>&1; then
        log_info "Xray 已存在，跳过下载"
    else
        log_info "下载 Xray..."
        XRAY_ZIP="${WORK_DIR}/xray.zip"

        if ! download_file "$XRAY_DL" "$XRAY_ZIP"; then
            log_err "下载 Xray 失败"
            read -p "是否回滚并清理所有文件？[Y/n]: " rollback_choice
            rollback_choice=$(trim "$rollback_choice")
            if [[ ! "$rollback_choice" =~ ^[Nn]$ ]]; then
                rollback_install
            fi
            exit 1
        fi

        if ! unzip_file "$XRAY_ZIP" "$WORK_DIR"; then
            log_err "解压 Xray 失败"
            read -p "是否回滚并清理所有文件？[Y/n]: " rollback_choice
            rollback_choice=$(trim "$rollback_choice")
            if [[ ! "$rollback_choice" =~ ^[Nn]$ ]]; then
                rollback_install
            fi
            exit 1
        fi

        chmod +x ${XRAY_BIN}

        # 清理 ZIP 文件和其他临时文件
        rm -f "$XRAY_ZIP"
        clean_work_dir "xray" "geoip.dat" "geosite.dat"
    fi

    # 3. 配置参数（带验证）
    if is_non_interactive; then
        # 非交互模式：端口已在 run_direct_install_non_interactive 中设置
        log_info "使用端口: ${PORT}"
    else
        # 交互模式：询问端口
        while true; do
            read -p "设置端口 (默认 8080): " PORT_INPUT
            PORT_INPUT=$(trim "$PORT_INPUT")

            if [[ -z "$PORT_INPUT" ]]; then
                PORT=8080
            else
                if ! validate_port "$PORT_INPUT"; then
                    continue
                fi
                PORT=$PORT_INPUT
            fi

            # 检查端口是否被占用
            if ! check_port_available "$PORT"; then
                local process_info
                process_info=$(get_port_process "$PORT")
                log_warn "端口 ${PORT} 已被占用 (${process_info})"
                read -p "是否强制使用此端口？[y/N]: " force_choice
                force_choice=$(trim "$force_choice")
                if [[ ! "$force_choice" =~ ^[Yy]$ ]]; then
                    continue
                fi
            fi
            break
        done
    fi

    UUID=$(cat /proc/sys/kernel/random/uuid)
    PATH_STR="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)"

    # 4. 生成 inbound JSON 并添加到统一配置
    local inbound_json="{ \"tag\": \"direct-${PORT}\", \"port\": ${PORT}, \"protocol\": \"vless\", \"settings\": { \"clients\": [{ \"id\": \"${UUID}\" }], \"decryption\": \"none\" }, \"streamSettings\": { \"network\": \"ws\", \"wsSettings\": { \"path\": \"${PATH_STR}\" } } }"

    add_inbound_to_config "$inbound_json" "direct" "${PORT}"

    # 获取 Xray 启动参数
    local xray_args
    xray_args=$(get_xray_start_args)
    
    # 保存直连模式信息
    DIRECT_INFO="${WORK_DIR}/.direct_info"
    cat > "$DIRECT_INFO" <<EOF
PORT=${PORT}
UUID=${UUID}
PATH=${PATH_STR}
EOF
    chmod 600 "$DIRECT_INFO"

    # 5. 启动/重启服务
    if service_exists "xray"; then
        log_info "重启 Xray 服务以应用新配置..."
        do_service_action "restart" "xray"
    else
        log_info "启动 Xray 服务..."
        setup_service "xray" "${XRAY_BIN}" "${xray_args}"
    fi

    # 6. 验证服务启动
    log_info "验证服务启动状态..."
    if ! verify_service_running "xray"; then
        log_err "服务启动失败"
        read -p "是否回滚并清理所有文件？[Y/n]: " rollback_choice
        rollback_choice=$(trim "$rollback_choice")
        if [[ ! "$rollback_choice" =~ ^[Nn]$ ]]; then
            rollback_install
        fi
        exit 1
    fi

    log_info "服务启动成功"

    # 7. 输出结果
    PUBLIC_IP=$(get_public_ip)
    LINK="vless://${UUID}@${PUBLIC_IP}:${PORT}?encryption=none&security=none&type=ws&path=${PATH_STR}#Direct_${PORT}"

    echo -e "\n${GREEN}=== 直连模式部署完成 ===${PLAIN}"
    echo -e "${CYAN}${LINK}${PLAIN}"

    echo ""
}
