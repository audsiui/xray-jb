#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 全局变量
WORK_DIR="/opt/xray-bundle"
XRAY_BIN="${WORK_DIR}/xray"
CF_BIN="${WORK_DIR}/cloudflared"
CONFIG_FILE="${WORK_DIR}/config.json"

log_info() { echo -e "${GREEN}[信息] $1${PLAIN}"; }
log_warn() { echo -e "${YELLOW}[警告] $1${PLAIN}"; }
log_err()  { echo -e "${RED}[错误] $1${PLAIN}"; }

# 去除两边空格
trim() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

# 验证端口
validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        log_err "端口必须是数字"
        return 1
    fi
    if [[ $port -lt 1 || $port -gt 65535 ]]; then
        log_err "端口范围必须在 1-65535 之间"
        return 1
    fi
    return 0
}

# 验证域名
validate_domain() {
    local domain="$1"
    if [[ -z "$domain" ]]; then
        log_err "域名不能为空"
        return 1
    fi
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_err "域名格式无效"
        return 1
    fi
    return 0
}

# 生成 vless 链接和二维码
generate_qr_url() {
    local mode="$1"
    local uuid="$2"
    local host="$3"
    local port="$4"
    local path="$5"
    local domain="${6:-}"
    local sni="${7:-$domain}"

    local base_url="https://audsiui.github.io/xray-jb/qrcode.html"
    local params="?mode=${mode}&uuid=${uuid}&host=${host}&port=${port}&path=${path}"

    if [[ "$mode" == "tunnel" && -n "$domain" ]]; then
        params="${params}&domain=${domain}"
        if [[ -n "$sni" ]]; then
            params="${params}&sni=${sni}"
        fi
    fi

    echo "${base_url}${params}"
}

# 信号处理
cleanup() {
    log_info "收到退出信号，正在关闭服务..."
    if [[ -n "$XRAY_PID" ]]; then
        kill "$XRAY_PID" 2>/dev/null
    fi
    if [[ -n "$CF_PID" ]]; then
        kill "$CF_PID" 2>/dev/null
    fi
    exit 0
}

trap cleanup SIGTERM SIGINT

# 主函数
main() {
    log_info "=== Xray Tunnel Docker 容器启动 ==="

    # 1. 验证必需的环境变量
    if [[ -z "$CF_TOKEN" ]]; then
        log_err "缺少必需环境变量: CF_TOKEN"
        exit 1
    fi

    if [[ -z "$DOMAIN" ]]; then
        log_err "缺少必需环境变量: DOMAIN"
        exit 1
    fi

    if [[ -z "$PORT" ]]; then
        log_err "缺少必需环境变量: PORT"
        exit 1
    fi

    # 验证端口
    if ! validate_port "$PORT"; then
        exit 1
    fi

    # 验证域名
    if ! validate_domain "$DOMAIN"; then
        exit 1
    fi

    # 优选域名（可选）
    OPT_DOMAIN="${OPT_DOMAIN:-cf.tencentapp.cn}"

    log_info "域名: ${DOMAIN}"
    log_info "端口: ${PORT}"
    log_info "优选域名: ${OPT_DOMAIN}"

    # 2. 生成 UUID 和 WS_PATH（UUID 前 4 位）
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}')")
    WS_PATH="${UUID:0:4}"

    log_info "UUID: ${UUID}"
    log_info "WS_PATH: ${WS_PATH}"

    # 3. 生成 Xray 配置文件（监听 127.0.0.1）
    cat > ${CONFIG_FILE} <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": ${PORT},
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": { "clients": [{ "id": "${UUID}" }], "decryption": "none" },
    "streamSettings": { "network": "ws", "wsSettings": { "path": "/${WS_PATH}" } }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

    chmod 600 ${CONFIG_FILE}
    log_info "Xray 配置文件已生成"

    # 4. 保存配置信息到文件（供查看）
    cat > "${WORK_DIR}/.info" <<EOF
UUID=${UUID}
WS_PATH=${WS_PATH}
DOMAIN=${DOMAIN}
OPT_DOMAIN=${OPT_DOMAIN}
PORT=${PORT}
EOF
    chmod 600 "${WORK_DIR}/.info"

    # 5. 启动 Xray（后台）
    log_info "启动 Xray..."
    ${XRAY_BIN} run -c ${CONFIG_FILE} &
    XRAY_PID=$!

    # 等待 Xray 启动
    sleep 2

    if ! kill -0 "$XRAY_PID" 2>/dev/null; then
        log_err "Xray 启动失败"
        exit 1
    fi
    log_info "Xray 启动成功 (PID: $XRAY_PID)"

    # 6. 启动 cloudflared（后台，通过环境变量传递 token）
    log_info "启动 Cloudflare Tunnel..."
    export CF_TOKEN="$CF_TOKEN"
    ${CF_BIN} tunnel --no-autoupdate run --token "$CF_TOKEN" &
    CF_PID=$!

    # 等待 cloudflared 启动
    sleep 2

    if ! kill -0 "$CF_PID" 2>/dev/null; then
        log_err "Cloudflared 启动失败，请检查 Token 是否正确"
        kill "$XRAY_PID" 2>/dev/null
        exit 1
    fi
    log_info "Cloudflared 启动成功 (PID: $CF_PID)"

    # 7. 生成连接信息
    LINK="vless://${UUID}@${OPT_DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=/${WS_PATH}&sni=${DOMAIN}#Tunnel_${DOMAIN}"
    QR_URL=$(generate_qr_url "tunnel" "$UUID" "$OPT_DOMAIN" "443" "/${WS_PATH}" "$DOMAIN" "$DOMAIN")

    echo ""
    echo -e "${GREEN}=== 部署成功 ===${PLAIN}"
    echo -e "${CYAN}${LINK}${PLAIN}"
    echo ""
    echo -e "${GREEN}二维码链接: ${PLAIN}${CYAN}${QR_URL}${PLAIN}"
    echo -e "${YELLOW}提示: 在手机浏览器打开上方链接即可扫描二维码${PLAIN}"
    echo ""

    # 8. 监控进程
    log_info "服务运行中，监控进程状态..."

    while true; do
        # 检查 Xray
        if ! kill -0 "$XRAY_PID" 2>/dev/null; then
            log_err "Xray 进程已退出！"
            exit 1
        fi

        # 检查 cloudflared
        if ! kill -0 "$CF_PID" 2>/dev/null; then
            log_err "Cloudflared 进程已退出！"
            exit 1
        fi

        sleep 10
    done
}

main
