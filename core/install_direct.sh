#!/bin/bash

run_direct_install() {
    # 1. 基础安装
    check_sys
    get_arch
    mkdir -p ${WORK_DIR}
    
    log_info "下载 Xray..."
    curl -L -o ${WORK_DIR}/xray.zip "$XRAY_DL"
    unzip -o ${WORK_DIR}/xray.zip -d ${WORK_DIR} >/dev/null 2>&1
    chmod +x ${XRAY_BIN}
    rm -f ${WORK_DIR}/xray.zip

    # 2. 配置参数
    read -p "设置端口 (默认 8080): " PORT
    [[ -z "${PORT}" ]] && PORT=8080
    
    UUID=$(cat /proc/sys/kernel/random/uuid)
    PATH_STR="/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)"
    
    # 3. 生成配置
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

    # 4. 启动服务 (调用 lib/service.sh)
    setup_service "xray-d" "${XRAY_BIN}" "run -c ${CONFIG_FILE}"
    
    # 5. 输出结果
    PUBLIC_IP=$(curl -s4m3 https://api.ipify.org || echo "127.0.0.1")
    LINK="vless://${UUID}@${PUBLIC_IP}:${PORT}?encryption=none&security=none&type=ws&path=${PATH_STR}#Direct_${PORT}"
    
    echo -e "\n${GREEN}=== 直连模式部署完成 ===${PLAIN}"
    echo -e "${CYAN}${LINK}${PLAIN}\n"
}