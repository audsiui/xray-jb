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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}"
        exit 1
    fi
}

log_info() { echo -e "${GREEN}[信息] $1${PLAIN}"; }
log_warn() { echo -e "${YELLOW}[警告] $1${PLAIN}"; }
log_err()  { echo -e "${RED}[错误] $1${PLAIN}"; }

# 去除两边空格
trim() {
    local var="$1"
    # 移除前导空格
    var="${var#"${var%%[![:space:]]*}"}"
    # 移除尾随空格
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
    # 基本域名格式验证（支持子域名）
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_err "域名格式无效"
        return 1
    fi
    return 0
}

# 获取公网IP（支持IPv4/IPv6回退）
get_public_ip() {
    local ip=""

    # 尝试 IPv4
    ip=$(curl -s4m3 --connect-timeout 3 https://api.ipify.org 2>/dev/null)
    if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
        echo "$ip"
        return 0
    fi

    # 尝试 IPv6
    ip=$(curl -s6m3 --connect-timeout 3 https://api.ipify.org 2>/dev/null)
    if [[ -n "$ip" ]]; then
        echo "$ip"
        return 0
    fi

    # 回退到 ip a 命令
    if command -v ip >/dev/null 2>&1; then
        # 获取第一个非本地IPv4地址
        ip=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | head -n 1)
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
        # 尝试 IPv6
        ip=$(ip -6 addr show 2>/dev/null | grep -oP '(?<=inet6\s)[0-9a-f:]+' | grep -v '^::1' | grep -v '^fe80' | head -n 1)
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
    fi

    # 最后回退到 127.0.0.1
    echo "127.0.0.1"
    return 0
}

# 验证服务是否启动成功
verify_service_running() {
    local service_name="$1"
    local max_wait=10
    local count=0

    while [[ $count -lt $max_wait ]]; do
        if command -v systemctl >/dev/null 2>&1; then
            systemctl is-active --quiet "$service_name" && return 0
        elif [[ -d "/etc/init.d" ]]; then
            rc-service "$service_name" status 2>/dev/null | grep -q "started" && return 0
        fi
        sleep 1
        ((count++))
    done

    return 1
}

# 下载文件（带验证和重试）
download_file() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0

    while [[ $retry_count -lt $max_retries ]]; do
        log_info "正在下载: $(basename "$output") (尝试 $((retry_count + 1))/$max_retries)"

        if curl -fL --progress-bar -o "$output" "$url"; then
            # 验证文件是否为空
            if [[ -s "$output" ]]; then
                echo ""  # 换行，让进度条后的输出更整洁
                return 0
            else
                echo ""
                log_err "下载的文件为空"
            fi
        else
            echo ""
            log_err "下载失败: curl 返回错误"
        fi

        ((retry_count++))

        if [[ $retry_count -lt $max_retries ]]; then
            read -p "是否重试下载？[Y/n]: " retry_choice
            retry_choice=$(trim "$retry_choice")
            if [[ "$retry_choice" =~ ^[Nn]$ ]]; then
                return 1
            fi
        fi
    done

    log_err "下载失败，已达到最大重试次数"
    return 1
}

# 解压 ZIP 文件（带验证）
unzip_file() {
    local zip_file="$1"
    local dest_dir="$2"

    if ! command -v unzip >/dev/null 2>&1; then
        log_err "unzip 命令不存在，请先安装"
        return 1
    fi

    # 验证 ZIP 文件
    if ! unzip -t "$zip_file" >/dev/null 2>&1; then
        log_err "ZIP 文件损坏或无效"
        return 1
    fi

    if unzip -o "$zip_file" -d "$dest_dir" >/dev/null 2>&1; then
        return 0
    else
        log_err "解压失败"
        return 1
    fi
}

# 回滚并清理
rollback_install() {
    log_warn "正在回滚安装..."

    # 停止并移除可能创建的服务
    remove_service "xray-d" >/dev/null 2>&1
    remove_service "xray-t" >/dev/null 2>&1
    remove_service "cloudflared-t" >/dev/null 2>&1

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1
    fi

    # 彻底清理工作目录
    if [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi

    log_info "回滚完成"
}

# 清理工作目录（保留指定文件）
clean_work_dir() {
    local keep_files=("$@")

    if [[ ! -d "$WORK_DIR" ]]; then
        return 0
    fi

    # 删除目录下所有文件，除了指定的
    for file in "$WORK_DIR"/*; do
        if [[ -f "$file" ]]; then
            local should_keep=false
            for keep in "${keep_files[@]}"; do
                if [[ "$(basename "$file")" == "$keep" ]]; then
                    should_keep=true
                    break
                fi
            done
            if [[ "$should_keep" == "false" ]]; then
                rm -f "$file"
            fi
        fi
    done
}