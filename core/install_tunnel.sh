#!/bin/bash

run_tunnel_install() {
    check_sys
    get_arch
    mkdir -p ${WORK_DIR}

    # 1. 下载组件（带验证和重试）
    log_info "下载组件..."

    # 下载 Xray
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

    # 清理 Xray ZIP 文件
    rm -f "$XRAY_ZIP"

    # 下载 cloudflared（如果不存在）
    if [[ ! -f "$CF_BIN" ]]; then
        if ! download_file "$CF_DL" "$CF_BIN"; then
            log_err "下载 cloudflared 失败"
            read -p "是否回滚并清理所有文件？[Y/n]: " rollback_choice
            rollback_choice=$(trim "$rollback_choice")
            if [[ ! "$rollback_choice" =~ ^[Nn]$ ]]; then
                rollback_install
            fi
            exit 1
        fi
        chmod +x ${CF_BIN}
    fi

    # 清理其他临时文件
    clean_work_dir "xray" "geoip.dat" "geosite.dat" "cloudflared"

    # 2. 获取输入（带验证）
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
            break
        fi

        if validate_port "$PORT_INPUT"; then
            PORT=$PORT_INPUT
            break
        fi
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
        read -p "是否回滚并清理所有文件？[Y/n]: " rollback_choice
        rollback_choice=$(trim "$rollback_choice")
        if [[ ! "$rollback_choice" =~ ^[Nn]$ ]]; then
            rollback_install
        fi
        exit 1
    fi

    if ! verify_service_running "cloudflared-t"; then
        log_warn "Cloudflared 服务可能还在启动中（需要连接 CF）"
    else
        log_info "Cloudflared 服务启动成功"
    fi

    log_info "服务启动成功"

    # 6. 输出
    LINK="vless://${UUID}@cf.tencentapp.cn:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${PATH_STR}&sni=${DOMAIN}#Tunnel_${DOMAIN}"

    echo -e "\n${GREEN}=== Tunnel 模式部署完成 ===${PLAIN}"
    echo -e "${CYAN}${LINK}${PLAIN}\n"
}
