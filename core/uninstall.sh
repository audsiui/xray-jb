#!/bin/bash

run_uninstall() {
    log_warn "正在卸载所有服务..."

    # 调用 lib/service.sh 中的移除函数
    remove_service "xray-d"
    remove_service "xray-t"
    remove_service "cloudflared-t"

    if command -v systemctl >/dev/null; then systemctl daemon-reload; fi

    # 清理临时文件
    rm -f /tmp/cloudflared_token.sh

    log_warn "清理文件: ${WORK_DIR}"
    rm -rf ${WORK_DIR}

    echo -e "${GREEN}卸载完成！${PLAIN}"
}
