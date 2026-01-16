#!/bin/bash

# 非交互式安装入口
run_tunnel_install_non_interactive() {
    # 验证必需参数
    if [[ -z "$ARG_TOKEN" ]]; then
        log_err "隧道模式需要 Token 参数 (--token)"
        exit 1
    fi
    if [[ -z "$ARG_DOMAIN" ]]; then
        log_err "隧道模式需要域名参数 (--domain)"
        exit 1
    fi

    # 使用命令行参数或默认值
    CF_TOKEN="$ARG_TOKEN"
    DOMAIN="$ARG_DOMAIN"
    PORT="${ARG_PORT:-10086}"
    # 优选域名：如果未指定则使用默认值
    OPT_DOMAIN="${ARG_OPT_DOMAIN:-cf.tencentapp.cn}"

    # 检查端口是否被占用（非交互模式下直接使用）
    if ! check_port_available "$PORT"; then
        local process_info
        process_info=$(get_port_process "$PORT")
        log_warn "端口 ${PORT} 已被占用 (${process_info})"
        log_warn "非交互模式将强制使用此端口"
    fi

    _do_tunnel_install
}

# 交互式安装入口
run_tunnel_install() {
    # 检测是否已安装
    if ! check_existing_install "tunnel"; then
        return 1
    fi

    _do_tunnel_install
}

# 实际安装逻辑
_do_tunnel_install() {
    check_sys
    get_arch
    mkdir -p ${WORK_DIR}

    # 1. 下载组件（带验证和重试）
    log_info "下载组件..."

    # 下载 Xray
    XRAY_ZIP="${WORK_DIR}/xray.zip"
    if ! download_file "$XRAY_DL" "$XRAY_ZIP"; then
        log_err "下载 Xray 失败"
        if ! is_non_interactive; then
            read -p "是否回滚并清理所有文件？[Y/n]: " rollback_choice
            rollback_choice=$(trim "$rollback_choice")
            if [[ ! "$rollback_choice" =~ ^[Nn]$ ]]; then
                rollback_install
            fi
        fi
        exit 1
    fi

    if ! unzip_file "$XRAY_ZIP" "$WORK_DIR"; then
        log_err "解压 Xray 失败"
        if ! is_non_interactive; then
            read -p "是否回滚并清理所有文件？[Y/n]: " rollback_choice
            rollback_choice=$(trim "$rollback_choice")
            if [[ ! "$rollback_choice" =~ ^[Nn]$ ]]; then
                rollback_install
            fi
        fi
        exit 1
    fi

    chmod +x ${XRAY_BIN}

    # 清理 Xray ZIP 文件
    rm -f "$XRAY_ZIP"

    # 下载 cloudflared（如果不存在）
    if [[ ! -f "$CF_BIN" ]]; then
        if ! download_file "$CF_DL" "$CF_BIN"; then
            log_err "下载 cloudflared 失败"
            if ! is_non_interactive; then
                read -p "是否回滚并清理所有文件？[Y/n]: " rollback_choice
                rollback_choice=$(trim "$rollback_choice")
                if [[ ! "$rollback_choice" =~ ^[Nn]$ ]]; then
                    rollback_install
                fi
            fi
            exit 1
        fi
        chmod +x ${CF_BIN}
    fi

    # 清理其他临时文件
    clean_work_dir "xray" "geoip.dat" "geosite.dat" "cloudflared"

    # 2. 获取输入（带验证）
    if is_non_interactive; then
        # 非交互模式：参数已在 run_tunnel_install_non_interactive 中设置
        log_info "使用域名: ${DOMAIN}"
        log_info "使用端口: ${PORT}"
    else
        # 交互模式
        log_warn "前提: 请在 CF 后台设置 Service 指向 http://localhost:端口"

        # Token 验证
        while true; do
            read -p "Cloudflare Token: " CF_TOKEN_INPUT
            CF_TOKEN_INPUT=$(trim "$CF_TOKEN_INPUT")

            if [[ -z "$CF_TOKEN_INPUT" ]]; then
                log_err "Token 不能为空"
                continue
            fi

            # 基本格式验证（CF Token 通常较长）
            if [[ ${#CF_TOKEN_INPUT} -lt 20 ]]; then
                log_warn "Token 长度似乎过短，请确认"
                read -p "是否继续使用此 Token？[y/N]: " confirm
                confirm=$(trim "$confirm")
                if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                    continue
                fi
            fi

            CF_TOKEN="$CF_TOKEN_INPUT"
            break
        done

        # 端口验证
        while true; do
            read -p "本地监听端口 (默认 10086): " PORT_INPUT
            PORT_INPUT=$(trim "$PORT_INPUT")

            if [[ -z "$PORT_INPUT" ]]; then
                PORT=10086
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

        # 域名验证
        while true; do
            read -p "绑定域名 (如 v.com): " DOMAIN_INPUT
            DOMAIN_INPUT=$(trim "$DOMAIN_INPUT")

            if [[ -z "$DOMAIN_INPUT" ]]; then
                log_err "域名不能为空"
                continue
            fi

            if validate_domain "$DOMAIN_INPUT"; then
                DOMAIN="$DOMAIN_INPUT"
                break
            fi
        done

        # 优选域名（可选）
        read -p "优选域名 (默认 cf.tencentapp.cn，直接回车使用默认): " OPT_DOMAIN_INPUT
        OPT_DOMAIN_INPUT=$(trim "$OPT_DOMAIN_INPUT")

        if [[ -z "$OPT_DOMAIN_INPUT" ]]; then
            OPT_DOMAIN="cf.tencentapp.cn"
            log_info "使用默认优选域名: cf.tencentapp.cn"
        else
            if validate_domain "$OPT_DOMAIN_INPUT"; then
                OPT_DOMAIN="$OPT_DOMAIN_INPUT"
                log_info "使用自定义优选域名: $OPT_DOMAIN"
            else
                log_warn "优选域名格式无效，使用默认值"
                OPT_DOMAIN="cf.tencentapp.cn"
            fi
        fi
    fi

    UUID=$(cat /proc/sys/kernel/random/uuid)
    PATH_STR="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)"

    # 3. 生成配置（监听 127.0.0.1）
    cat > ${CONFIG_FILE} <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": ${PORT},
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": { "clients": [{ "id": "${UUID}" }], "decryption": "none" },
    "streamSettings": { "network": "ws", "wsSettings": { "path": "${PATH_STR}" } }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

    # 设置配置文件权限
    chmod 600 ${CONFIG_FILE}

    # 创建 Token 配置文件（避免暴露在命令行）
    CF_TOKEN_FILE="${WORK_DIR}/.cf_token"
    echo "$CF_TOKEN" > "$CF_TOKEN_FILE"
    chmod 600 "$CF_TOKEN_FILE"

    # 保存域名信息（用于后续查看配置链接）
    DOMAIN_INFO_FILE="${WORK_DIR}/.domain_info"
    cat > "$DOMAIN_INFO_FILE" <<EOF
DOMAIN=${DOMAIN}
OPT_DOMAIN=${OPT_DOMAIN}
EOF
    chmod 600 "$DOMAIN_INFO_FILE"

    # 4. 启动双服务
    setup_service "xray-t" "${XRAY_BIN}" "run -c ${CONFIG_FILE}"

    # 使用环境变量传递 Token（更安全）
    cat > /tmp/cloudflared_token.sh <<EOF
#!/bin/bash
export CF_TOKEN="$CF_TOKEN"
exec ${CF_BIN} tunnel --no-autoupdate run --token \${CF_TOKEN}
EOF
    chmod +x /tmp/cloudflared_token.sh
    setup_service "cloudflared-t" "/bin/bash" "/tmp/cloudflared_token.sh"

    # 5. 验证服务启动
    log_info "验证服务启动状态..."
    if ! verify_service_running "xray-t"; then
        log_err "Xray 服务启动失败"
        if ! is_non_interactive; then
            read -p "是否回滚并清理所有文件？[Y/n]: " rollback_choice
            rollback_choice=$(trim "$rollback_choice")
            if [[ ! "$rollback_choice" =~ ^[Nn]$ ]]; then
                rollback_install
            fi
        fi
        exit 1
    fi

    if ! verify_service_running "cloudflared-t"; then
        log_warn "Cloudflared 服务可能还在启动中（需要连接 CF）"
    else
        log_info "Cloudflared 服务启动成功"
    fi

    log_info "服务启动成功"

    # 6. 输出（使用优选 IP 域名作为连接地址）
    LINK="vless://${UUID}@${OPT_DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${PATH_STR}&sni=${DOMAIN}#Tunnel_${DOMAIN}"

    echo -e "\n${GREEN}=== Tunnel 模式部署完成 ===${PLAIN}"
    echo -e "${CYAN}${LINK}${PLAIN}"

    # 显示二维码（如果请求）
    if [[ "$ARG_QR" == "true" ]]; then
        show_qr_code "$LINK"
    fi
    echo ""
}
