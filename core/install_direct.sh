#!/bin/bash

run_direct_install() {
    # 检测是否已安装
    if ! check_existing_install "direct"; then
        return 1
    fi

    # 1. 基础安装
    check_sys
    get_arch
    mkdir -p ${WORK_DIR}

    # 2. 下载 Xray（带验证和重试）
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

    # 3. 配置参数（带验证）
    while true; do
        read -p "设置端口 (默认 8080): " PORT_INPUT
        PORT_INPUT=$(trim "$PORT_INPUT")

        if [[ -z "$PORT_INPUT" ]]; then
            PORT=8080
            break
        fi

        if validate_port "$PORT_INPUT"; then
            PORT=$PORT_INPUT
            break
        fi
    done

    UUID=$(cat /proc/sys/kernel/random/uuid)
    PATH_STR="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)"

    # 4. 生成配置
    cat > ${CONFIG_FILE} <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": ${PORT},
    "protocol": "vless",
    "settings": { "clients": [{ "id": "${UUID}" }], "decryption": "none" },
    "streamSettings": { "network": "ws", "wsSettings": { "path": "${PATH_STR}" } }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

    # 设置配置文件权限
    chmod 600 ${CONFIG_FILE}

    # 5. 启动服务
    setup_service "xray-d" "${XRAY_BIN}" "run -c ${CONFIG_FILE}"

    # 6. 验证服务启动
    log_info "验证服务启动状态..."
    if ! verify_service_running "xray-d"; then
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
    echo -e "${CYAN}${LINK}${PLAIN}\n"
}
