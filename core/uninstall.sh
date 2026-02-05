#!/bin/bash

run_uninstall() {
    log_warn "正在卸载所有服务..."

    # 调用 lib/service.sh 中的移除函数
    remove_service "xray"
    remove_service "cloudflared-t"

    if command -v systemctl >/dev/null; then systemctl daemon-reload; fi

    # 清理临时文件
    rm -f /tmp/cloudflared_token.sh

    log_warn "清理文件: ${WORK_DIR}"
    # 清理所有配置文件和二进制文件
    rm -f "${WORK_DIR}/config.json"
    rm -f "${WORK_DIR}/.direct_info"
    rm -f "${WORK_DIR}/.domain_info"
    rm -f "${WORK_DIR}/.reality_keys"
    rm -f "${WORK_DIR}/.xhttp_info"
    rm -f "${WORK_DIR}/.cf_token"
    rm -f "${WORK_DIR}/xray"
    rm -f "${WORK_DIR}/cloudflared"
    rm -f "${WORK_DIR}/xray.bak"
    rm -f "${WORK_DIR}/cloudflared.bak"
    rm -f "${WORK_DIR}/geoip.dat"
    rm -f "${WORK_DIR}/geosite.dat"
    rm -rf "${WORK_DIR}/logs"

    # 如果目录为空则删除
    rmdir "${WORK_DIR}" 2>/dev/null || true

    echo -e "${GREEN}卸载完成！${PLAIN}"
}
