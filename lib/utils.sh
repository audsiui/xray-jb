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
# Xray 配置目录（多节点统一配置）
CONFS_DIR="${WORK_DIR}/confs"
LOG_DIR="${WORK_DIR}/logs"
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB

# 检查 Xray 服务是否存在
has_xray_service() {
    if command -v systemctl >/dev/null 2>&1; then
        [[ -f "/etc/systemd/system/xray.service" ]]
    elif [[ -d "/etc/init.d" ]]; then
        [[ -f "/etc/init.d/xray" ]]
    else
        return 1
    fi
}

# 初始化多文件配置目录
init_confs_dir() {
    if [[ ! -d "$CONFS_DIR" ]]; then
        mkdir -p "$CONFS_DIR"
        chmod 755 "$CONFS_DIR"
    fi

    # 创建基础配置文件（日志）
    if [[ ! -f "${CONFS_DIR}/00_log.json" ]]; then
        cat > "${CONFS_DIR}/00_log.json" <<'EOF'
{
  "log": { "loglevel": "warning", "access": "none" }
}
EOF
        chmod 600 "${CONFS_DIR}/00_log.json"
    fi

    # 创建基础 outbounds 文件
    if [[ ! -f "${CONFS_DIR}/99_outbounds.json" ]]; then
        cat > "${CONFS_DIR}/99_outbounds.json" <<'EOF'
{
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
        chmod 600 "${CONFS_DIR}/99_outbounds.json"
    fi
}

# 添加 inbound 配置（创建单独的配置文件）
# 参数：$1=inbound_json, $2=mode_name (如: ws, reality, xhttp), $3=port
add_inbound_to_config() {
    local inbound_json="$1"
    local mode_name="$2"
    local port="$3"

    # 初始化配置目录
    init_confs_dir

    # 生成配置文件名（使用前缀确保加载顺序）
    # 10_ws_8080.json, 20_reality_8443.json, 30_xhttp_8081.json
    local prefix
    case "$mode_name" in
        ws|direct) prefix="10" ;;
        reality)   prefix="20" ;;
        xhttp)     prefix="30" ;;
        tunnel)    prefix="40" ;;
        *)         prefix="50" ;;
    esac

    local conf_file="${CONFS_DIR}/${prefix}_${mode_name}_${port}.json"

    # 创建单独的 inbound 配置文件
    cat > "$conf_file" <<EOF
{
  "inbounds": [$inbound_json]
}
EOF
    chmod 600 "$conf_file"

    log_info "配置已保存到: ${conf_file}"
}

# 删除指定模式的 inbound 配置
remove_inbound_config() {
    local mode_name="$1"
    local port="$2"

    if [[ -z "$port" ]]; then
        # 删除该模式的所有配置文件
        for f in "${CONFS_DIR}"/*_${mode_name}_*.json; do
            [[ -e "$f" ]] || continue
            if [[ -f "$f" ]]; then
                rm -f "$f"
                log_info "已移除配置: ${f}"
            fi
        done
    else
        # 删除指定端口的配置文件
        for f in "${CONFS_DIR}"/*_${mode_name}_${port}.json; do
            [[ -e "$f" ]] || continue
            if [[ -f "$f" ]]; then
                rm -f "$f"
                log_info "已移除配置: ${f}"
            fi
        done
    fi
}

# 获取 Xray 启动参数（confdir 模式）
get_xray_start_args() {
    echo "run -confdir ${CONFS_DIR}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}"
        exit 1
    fi
}

log_info() { echo -e "${GREEN}[信息] $1${PLAIN}"; }
log_warn() { echo -e "${YELLOW}[警告] $1${PLAIN}"; }
log_err()  { echo -e "${RED}[错误] $1${PLAIN}"; }

# 初始化日志目录
init_log_dir() {
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
    fi
}

# 日志轮转（保留最近3个备份）
rotate_log() {
    local log_file="$1"
    local max_backups=3

    # 文件不存在或太小则跳过
    if [[ ! -f "$log_file" ]]; then
        return 0
    fi

    local file_size
    file_size=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null || echo 0)

    if [[ $file_size -lt $MAX_LOG_SIZE ]]; then
        return 0
    fi

    # 轮转备份文件
    for ((i = max_backups - 1; i >= 1; i--)); do
        local old_backup="${log_file}.${i}"
        local new_backup="${log_file}.$((i + 1))"
        if [[ -f "$old_backup" ]]; then
            mv "$old_backup" "$new_backup" 2>/dev/null
        fi
    done

    # 当前日志转为 .1
    mv "$log_file" "${log_file}.1" 2>/dev/null
}

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

# 检测端口是否被占用
check_port_available() {
    local port="$1"

    # 优先使用 ss 命令（更快更准确）
    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":${port} "; then
            return 1
        fi
    # 回退到 netstat
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            return 1
        fi
    # 最后回退到 lsof
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -i ":${port}" >/dev/null 2>&1; then
            return 1
        fi
    fi

    return 0
}

# 获取占用端口的进程信息
get_port_process() {
    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        ss -tulnp | grep ":${port} " | awk '{print $6}'
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tulnp 2>/dev/null | grep ":${port} " | awk '{print $7}'
    elif command -v lsof >/dev/null 2>&1; then
        lsof -i ":${port}" | tail -n +2 | awk '{print $1}'
    fi
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
        # 获取第一个非本地IPv4地址（用 sed 替代 grep -oP，busybox 无 PCRE）
        ip=$(ip -4 addr show 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*$/\1/p' | grep -v '^127\.' | head -n 1)
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
        # 尝试 IPv6（排除回环与链路本地地址）
        ip=$(ip -6 addr show 2>/dev/null | sed -n 's/.*inet6 \([0-9a-f:]*\).*$/\1/p' \
                | grep -v '^::1' | grep -v '^fe80' | head -n 1)
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

# 解压 ZIP 文件
# 注：不使用 unzip -t 预检，busybox 的 unzip 不支持 -t；
# 文件损坏时解压命令本身会失败，效果等同。
unzip_file() {
    local zip_file="$1"
    local dest_dir="$2"

    if ! command -v unzip >/dev/null 2>&1; then
        log_err "unzip 命令不存在，请先安装"
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
    remove_service "xray" >/dev/null 2>&1
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

# 清理工作目录（保留指定文件和目录）
clean_work_dir() {
    local keep_items=("$@")

    if [[ ! -d "$WORK_DIR" ]]; then
        return 0
    fi

    # 删除目录下所有文件和目录，除了指定的
    for file in "$WORK_DIR"/*; do
        local basename=$(basename "$file")
        local should_keep=false

        # 检查是否在保留列表中
        for keep in "${keep_items[@]}"; do
            if [[ "$basename" == "$keep" ]]; then
                should_keep=true
                break
            fi
        done

        # 始终保留 confs 目录（配置分片目录）
        if [[ "$basename" == "confs" ]]; then
            should_keep=true
        fi

        if [[ "$should_keep" == "false" ]]; then
            rm -rf "$file"
        fi
    done
}

# 检测指定模式是否已安装（通过检查 confs 目录中的配置文件）
check_mode_exists() {
    local mode="$1"
    local port="${2:-}"

    if [[ -n "$port" ]]; then
        # 检查特定端口的配置
        for f in "${CONFS_DIR}"/*_${mode}_${port}.json; do
            [[ -e "$f" ]] || continue
            [[ -f "$f" ]] && return 0
        done
    else
        # 检查该模式是否有任何配置
        for f in "${CONFS_DIR}"/*_${mode}_*.json; do
            [[ -e "$f" ]] || continue
            [[ -f "$f" ]] && return 0
        done
    fi
    return 1
}

# 检测服务是否已安装（同模式支持多节点，仅提示不阻断；
# 返回 1 仅当同模式同端口节点已存在，避免覆盖现有配置）
check_existing_install() {
    local mode="$1"
    local port="${2:-}"

    if [[ -n "$port" ]] && check_mode_exists "$mode" "$port"; then
        log_err "${mode} 模式端口 ${port} 的节点已存在"
        log_err "如需重建请先在节点管理中删除该节点，或更换其他端口"
        return 1
    fi

    if check_mode_exists "$mode"; then
        log_info "已存在 ${mode} 模式节点，本次将添加新节点"
    fi

    return 0
}

# ========== 节点注册表 ==========
# 每个节点一个信息文件: ${WORK_DIR}/nodes/<mode>_<port>.info (KEY=VAL 格式)
# 公共字段: MODE, PORT, UUID；其余为各模式专有字段
NODES_DIR="${WORK_DIR}/nodes"

# 初始化节点目录
init_nodes_dir() {
    if [[ ! -d "$NODES_DIR" ]]; then
        mkdir -p "$NODES_DIR"
        chmod 700 "$NODES_DIR"
    fi
}

# 保存节点信息（调用前先设置好对应变量）
save_node_info() {
    local mode="$1" port="$2"
    init_nodes_dir

    local info_file="${NODES_DIR}/${mode}_${port}.info"
    {
        echo "MODE=${mode}"
        echo "PORT=${port}"
        echo "UUID=${UUID}"
        case "$mode" in
            direct)  echo "PATH=${PATH_STR}" ;;
            xhttp)   echo "PATH=${PATH_STR}" ;;
            tunnel)
                echo "PATH=${PATH_STR}"
                echo "DOMAIN=${DOMAIN}"
                echo "OPT_DOMAIN=${OPT_DOMAIN}"
                ;;
            reality)
                echo "PRIVATE_KEY=${PRIVATE_KEY}"
                echo "PUBLIC_KEY=${PUBLIC_KEY}"
                echo "SHORT_ID=${SHORT_ID}"
                echo "DOMAIN=${DOMAIN}"
                ;;
        esac
    } > "$info_file"
    chmod 600 "$info_file"
    log_info "节点信息已保存: ${info_file}"
}

# 删除节点信息文件
remove_node_info() {
    local mode="$1" port="$2"
    local info_file="${NODES_DIR}/${mode}_${port}.info"
    if [[ -f "$info_file" ]]; then
        rm -f "$info_file"
        log_info "已移除节点信息: ${info_file}"
    fi
}

# 列出节点信息文件（可选按模式过滤），每行一个路径
list_node_files() {
    local mode="${1:-}"
    init_nodes_dir
    local pattern="*"
    [[ -n "$mode" ]] && pattern="${mode}_*"
    for f in "${NODES_DIR}"/${pattern}.info; do
        [[ -f "$f" ]] || continue
        echo "$f"
    done | sort
}

# 首次运行后持久化脚本并创建 xj 快捷命令
ensure_xj_command() {
    local script_dest="${WORK_DIR}/scripts"

    # 同步脚本文件到持久化目录（内容变化时才覆盖）
    if [[ -d "$script_dest" ]] && \
       cmp -s "${SCRIPT_DIR}/main.sh" "${script_dest}/main.sh" && \
       diff -rq "${SCRIPT_DIR}/lib" "${script_dest}/lib" >/dev/null 2>&1 && \
       diff -rq "${SCRIPT_DIR}/core" "${script_dest}/core" >/dev/null 2>&1; then
        : # 无变化
    else
        mkdir -p "$script_dest"
        cp -f "${SCRIPT_DIR}/main.sh" "$script_dest/" 2>/dev/null || true
        rm -rf "${script_dest}/lib" "${script_dest}/core"
        cp -rf "${SCRIPT_DIR}/lib" "${SCRIPT_DIR}/core" "$script_dest/" 2>/dev/null || true
        log_info "脚本已安装到: ${script_dest}"
    fi

    # 创建 xj 快捷命令
    local xj_bin="/usr/local/bin/xj"
    if [[ ! -x "$xj_bin" ]] || ! grep -qF "${script_dest}/main.sh" "$xj_bin" 2>/dev/null; then
        printf '#!/bin/bash\nexec bash %s/main.sh "$@"\n' "${script_dest}" > "$xj_bin"
        chmod +x "$xj_bin"
        log_info "快捷命令已创建: 直接输入 ${GREEN}xj${PLAIN} 即可打开管理菜单"
    fi
}

# 获取所有已安装的模式（通过检查 confs 目录）
get_installed_modes() {
    local modes=""

    # 通过检查 confs 目录中的配置文件来确定已安装的模式
    if [[ -d "$CONFS_DIR" ]]; then
        for f in "${CONFS_DIR}"/*.json; do
            [[ -e "$f" ]] || continue
            [[ -f "$f" ]] || continue
            local basename=$(basename "$f")
            # 从文件名中提取模式（如 10_direct_8080.json -> direct）
            if [[ "$basename" =~ ^[0-9]+_([a-z]+)_[0-9]+\.json$ ]]; then
                local mode="${BASH_REMATCH[1]}"
                # 避免重复添加
                if [[ " $modes " != *" $mode "* ]]; then
                    modes="${modes}${mode} "
                fi
            fi
        done
    fi

    echo "$modes"
}

