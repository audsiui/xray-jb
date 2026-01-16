#!/bin/bash

run_tunnel_install() {
    check_sys
    get_arch
    mkdir -p ${WORK_DIR}
    
    # 1. 下载组件
    log_info "下载组件..."
    curl -L -o ${WORK_DIR}/xray.zip "$XRAY_DL"
    unzip -o ${WORK_DIR}/xray.zip -d ${WORK_DIR} >/dev/null 2>&1
    chmod +x ${XRAY_BIN}
    
    if [[ ! -f "$CF_BIN" ]]; then
        curl -L -o ${CF_BIN} "$CF_DL"
        chmod +x ${CF_BIN}
    fi

    # 2. 获取输入
    log_warn "前提: 请在 CF 后台设置 Service 指向 http://localhost:端口"
    read -p "Cloudflare Token: " CF_TOKEN
    [[ -z "$CF_TOKEN" ]] && { log_err "Token 不能为空"; exit 1; }
    
    read -p "本地监听端口 (默认 10086): " PORT
    [[ -z "${PORT}" ]] && PORT=10086
    
    read -p "绑定域名 (如 v.com): " DOMAIN

    UUID=$(cat /proc/sys/kernel/random/uuid)
    PATH_STR="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)"

    # 3. 生成配置 (监听 127.0.0.1)
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

    # 4. 启动双服务
    setup_service "xray-t" "${XRAY_BIN}" "run -c ${CONFIG_FILE}"
    setup_service "cloudflared-t" "${CF_BIN}" "tunnel --no-autoupdate run --token ${CF_TOKEN}"

    # 5. 输出
    LINK="vless://${UUID}@cf.tencentapp.cn:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${PATH_STR}&sni=${DOMAIN}#Tunnel_${DOMAIN}"
    
    echo -e "\n${GREEN}=== Tunnel 模式部署完成 ===${PLAIN}"
    echo -e "${CYAN}${LINK}${PLAIN}\n"
}