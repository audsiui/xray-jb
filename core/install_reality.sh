#!/bin/bash

# 非交互式安装入口
run_reality_install_non_interactive() {
    # 检测是否已安装 reality 模式
    if ! check_existing_install "reality"; then
        exit 1
    fi

    # 使用命令行参数或默认值
    PORT="${ARG_PORT:-8443}"
    DOMAIN="${ARG_DOMAIN:-www.microsoft.com}"

    # 检查端口是否被占用（非交互模式下直接使用）
    if ! check_port_available "$PORT"; then
        local process_info
        process_info=$(get_port_process "$PORT")
        log_warn "端口 ${PORT} 已被占用 (${process_info})"
        log_warn "非交互模式将强制使用此端口"
    fi

    _do_reality_install
}

# 交互式安装入口
run_reality_install() {
    # 检测是否已安装 reality 模式
    if ! check_existing_install "reality"; then
        return 1
    fi

    _do_reality_install
}

# 生成 X25519 密钥对
generate_reality_keys() {
    # 使用 xray 生成密钥对
    if [[ -f "${XRAY_BIN}" ]]; then
        # 检查 xray 是否可以执行（在 Alpine 上可能缺少库）
        if ! chmod +x "${XRAY_BIN}" 2>/dev/null; then
            log_warn "无法设置 Xray 执行权限"
        fi

        # 测试 xray 是否能正常运行
        local version_output
        version_output=$("${XRAY_BIN}" version 2>&1)
        if [[ -z "$version_output" ]]; then
            log_err "Xray 无法运行，可能是缺少依赖库"
            if [[ "$OS_TYPE" == "alpine" ]]; then
                log_info "正在尝试修复 Alpine 依赖..."
                apk add --no-cache libc6-compat gcompat 2>/dev/null || true
            fi
            return 1
        fi

        local keypair
        keypair=$("${XRAY_BIN}" x25519 2>&1)
        # 兼容新旧版本格式
        if [[ -n "$keypair" ]] && (echo "$keypair" | grep -q "PrivateKey:" || echo "$keypair" | grep -q "Private key:"); then
            echo "$keypair"
            return 0
        else
            log_err "Xray x25519 命令失败: ${keypair}"
        fi
    fi
    return 1
}

# 生成 shortId
generate_short_id() {
    # 生成 8 位十六进制 shortId
    local short_id
    if command -v xxd >/dev/null 2>&1; then
        short_id=$(head -c 4 /dev/urandom | xxd -p 2>/dev/null)
    else
        # Alpine 可能没有 xxd，使用 od 代替
        short_id=$(head -c 4 /dev/urandom | od -A n -t x1 | tr -d ' \n')
    fi
    echo "${short_id:-12345678}"
}

# 实际安装逻辑
_do_reality_install() {
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
        # 非交互模式：端口和域名已在 run_reality_install_non_interactive 中设置
        log_info "使用端口: ${PORT}"
        log_info "使用域名: ${DOMAIN}"
    else
        # 交互模式：询问端口
        while true; do
            read -p "设置端口 (默认 8443): " PORT_INPUT
            PORT_INPUT=$(trim "$PORT_INPUT")

            if [[ -z "$PORT_INPUT" ]]; then
                PORT=8443
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

        # 域名验证（用于伪装/SNI）
        while true; do
            read -p "伪装域名 (默认 www.microsoft.com): " DOMAIN_INPUT
            DOMAIN_INPUT=$(trim "$DOMAIN_INPUT")

            if [[ -z "$DOMAIN_INPUT" ]]; then
                DOMAIN="www.microsoft.com"
                break
            fi

            if validate_domain "$DOMAIN_INPUT"; then
                DOMAIN="$DOMAIN_INPUT"
                break
            fi
        done
    fi

    # 生成 UUID
    UUID=$(cat /proc/sys/kernel/random/uuid)

    # 生成 REALITY 密钥对
    log_info "生成 REALITY 密钥对..."
    local keypair
    keypair=$(generate_reality_keys)
    if [[ -z "$keypair" ]]; then
        log_err "生成密钥对失败，请检查 Xray 是否正确安装"
        log_err "在 Alpine 系统上，可能需要手动安装: apk add libc6-compat gcompat"
        read -p "是否使用默认密钥（不安全，仅用于测试）？[y/N]: " use_default_key
        use_default_key=$(trim "$use_default_key")
        if [[ "$use_default_key" =~ ^[Yy]$ ]]; then
            PRIVATE_KEY="MHg4ZTZjZTBkMi0wOWJiLTExZWYtYTI3NC0xMjM0NTY3ODkwYWJhYmNkZWYtMTIzNC0xMjNlLWE0NTYtNDI2NjE0MTc0MDAw"
            PUBLIC_KEY="0u9L2hfI-3gf4eOkT3rwdCw3mbn8CHw3yL3hCKf5xVw"
        else
            rollback_install
            exit 1
        fi
    else
        # 解析密钥（兼容新旧版本格式）
        # 新版本: PrivateKey / Password / Hash32
        # 旧版本: Private key / Public key
        PRIVATE_KEY=$(echo "$keypair" | awk -F': ' '/^PrivateKey:/{print $2}')
        if [[ -z "$PRIVATE_KEY" ]]; then
            PRIVATE_KEY=$(echo "$keypair" | awk -F': ' '/Private key/{print $2}')
        fi

        # 新版本的 Password 就是公钥（客户端用）
        PUBLIC_KEY=$(echo "$keypair" | awk -F': ' '/^Password:/{print $2}')
        if [[ -z "$PUBLIC_KEY" ]]; then
            PUBLIC_KEY=$(echo "$keypair" | awk -F': ' '/Public key/{print $2}')
        fi

        # 验证密钥格式
        if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
            log_err "解析密钥失败，原始输出:"
            echo "$keypair"
            rollback_install
            exit 1
        fi
    fi

    # 生成 shortId
    SHORT_ID=$(generate_short_id)

    # 4. 生成 inbound JSON 并添加到统一配置
    local inbound_json="{ \"tag\": \"reality-${PORT}\", \"port\": ${PORT}, \"protocol\": \"vless\", \"settings\": { \"clients\": [{ \"id\": \"${UUID}\", \"flow\": \"xtls-rprx-vision\" }], \"decryption\": \"none\" }, \"streamSettings\": { \"network\": \"tcp\", \"security\": \"reality\", \"realitySettings\": { \"show\": false, \"dest\": \"${DOMAIN}:443\", \"xver\": 0, \"serverNames\": [\"${DOMAIN}\"], \"privateKey\": \"${PRIVATE_KEY}\", \"shortIds\": [\"${SHORT_ID}\"] } }, \"sniffing\": { \"enabled\": true, \"destOverride\": [\"http\", \"tls\"] } }"

    add_inbound_to_config "$inbound_json" "reality" "${PORT}"

    # 获取 Xray 启动参数
    local xray_args
    xray_args=$(get_xray_start_args)
    
    # 保存密钥信息（用于显示给用户）
    KEYS_FILE="${WORK_DIR}/.reality_keys"
    cat > "$KEYS_FILE" <<EOF
PORT=${PORT}
UUID=${UUID}
PRIVATE_KEY=${PRIVATE_KEY}
PUBLIC_KEY=${PUBLIC_KEY}
SHORT_ID=${SHORT_ID}
DOMAIN=${DOMAIN}
EOF
    chmod 600 "$KEYS_FILE"

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

    # REALITY 分享链接格式
    # vless://uuid@ip:port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=domain&fp=chrome&pbk=public_key&sid=short_id&type=tcp#name
    LINK="vless://${UUID}@${PUBLIC_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#REALITY_${PORT}"

    echo -e "\n${GREEN}=== REALITY 模式部署完成 ===${PLAIN}"
    echo -e "${CYAN}${LINK}${PLAIN}"
    echo ""
    echo -e "${GREEN}配置信息:${PLAIN}"
    echo -e "  地址: ${CYAN}${PUBLIC_IP}${PLAIN}"
    echo -e "  端口: ${CYAN}${PORT}${PLAIN}"
    echo -e "  UUID: ${CYAN}${UUID}${PLAIN}"
    echo -e "  传输协议: ${CYAN}tcp${PLAIN}"
    echo -e "  安全协议: ${CYAN}reality${PLAIN}"
    echo -e "  Flow: ${CYAN}xtls-rprx-vision${PLAIN}"
    echo -e "  SNI: ${CYAN}${DOMAIN}${PLAIN}"
    echo -e "  公钥 (PublicKey): ${CYAN}${PUBLIC_KEY}${PLAIN}"
    echo -e "  ShortId: ${CYAN}${SHORT_ID}${PLAIN}"
    echo -e "  指纹 (Fingerprint): ${CYAN}chrome${PLAIN}"
    echo ""
    echo -e "${YELLOW}提示: 请妥善保存公钥和 ShortId，客户端连接时需要用到${PLAIN}"
    echo ""
}
