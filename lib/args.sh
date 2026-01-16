#!/bin/bash

# 命令行参数解析
# 用法: parse_args "$@"

# 全局变量（用于存储解析后的参数）
ARG_MODE=""           # 模式: direct, tunnel, uninstall, manage, update
ARG_PORT=""           # 端口
ARG_DOMAIN=""         # 域名（tunnel 模式）
ARG_TOKEN=""          # Cloudflare Token（tunnel 模式）
ARG_OPT_DOMAIN=""     # 优选域名（tunnel 模式，可选）
ARG_ACTION=""         # 服务管理操作: start, stop, restart, status
ARG_QUIET=false       # 静默模式
ARG_HELP=false        # 显示帮助
ARG_QR=false          # 显示二维码

# 显示帮助信息
show_help() {
    cat << 'EOF'
Xray + Tunnel 工程化部署脚本

用法:
    bash main.sh [选项] [参数]

安装模式:
    -m, --mode <MODE>          安装模式: direct(直连), tunnel(CF隧道)
    -p, --port <PORT>          端口号 (直连默认 8080, 隧道默认 10086)
    -d, --domain <DOMAIN>      域名 (tunnel 模式必需)
    -t, --token <TOKEN>        Cloudflare Tunnel Token (tunnel 模式必需)
    --opt-domain <DOMAIN>      优选域名 (tunnel 模式可选，默认 cf.tencentapp.cn)

服务管理:
    -M, --manage               进入服务管理子菜单
    -a, --action <ACTION>      服务操作: start, stop, restart, status

更新功能:
    -u, --update               更新 Xray 和 cloudflared 到最新版本

卸载:
    --uninstall                卸载所有服务并清理文件

其他选项:
    -q, --quiet                静默模式，减少输出
    --qr                       安装完成后显示二维码 (需 qrencode)
    -h, --help                 显示此帮助信息

示例:
    # 交互式安装（默认）
    bash main.sh

    # 非交互式直连模式安装
    bash main.sh --mode direct --port 443

    # 非交互式隧道模式安装
    bash main.sh --mode tunnel --port 10086 --domain example.com --token xxxx

    # 服务管理
    bash main.sh --manage --action status
    bash main.sh --manage --action restart

    # 更新版本
    bash main.sh --update

    # 安装并显示二维码
    bash main.sh --mode direct --port 443 --qr

服务管理子菜单选项:
    1. 查看服务状态        - 显示所有服务的运行状态
    2. 启动服务            - 启动已安装的服务
    3. 停止服务            - 停止正在运行的服务
    4. 重启服务            - 重启服务
    5. 查看详细状态        - 显示 systemctl/rc-service 详细输出
    6. 查看配置链接        - 显示 vless:// 链接
    7. 显示配置二维码      - 在终端显示二维码（需安装 qrencode）

EOF
}

# 解析命令行参数
parse_args() {
    # 如果没有参数，返回（使用交互模式）
    if [[ $# -eq 0 ]]; then
        return 0
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--mode)
                ARG_MODE="$2"
                shift 2
                ;;
            -p|--port)
                ARG_PORT="$2"
                shift 2
                ;;
            -d|--domain)
                ARG_DOMAIN="$2"
                shift 2
                ;;
            -t|--token)
                ARG_TOKEN="$2"
                shift 2
                ;;
            --opt-domain)
                ARG_OPT_DOMAIN="$2"
                shift 2
                ;;
            -M|--manage)
                ARG_MODE="manage"
                shift
                ;;
            -a|--action)
                ARG_ACTION="$2"
                shift 2
                ;;
            -u|--update)
                ARG_MODE="update"
                shift
                ;;
            --uninstall)
                ARG_MODE="uninstall"
                shift
                ;;
            -q|--quiet)
                ARG_QUIET=true
                shift
                ;;
            --qr)
                ARG_QR=true
                shift
                ;;
            -h|--help)
                ARG_HELP=true
                shift
                ;;
            *)
                log_err "未知参数: $1"
                log_err "使用 --help 查看帮助信息"
                exit 1
                ;;
        esac
    done

    # 处理帮助请求
    if [[ "$ARG_HELP" == "true" ]]; then
        show_help
        exit 0
    fi

    # 验证参数组合
    validate_args
}

# 验证参数组合
validate_args() {
    # 如果没有指定模式，使用默认交互模式
    if [[ -z "$ARG_MODE" ]]; then
        return 0
    fi

    case "$ARG_MODE" in
        direct)
            # 直连模式只需要端口
            if [[ -n "$ARG_PORT" ]]; then
                if ! validate_port "$ARG_PORT"; then
                    log_err "端口参数无效"
                    exit 1
                fi
            fi
            ;;
        tunnel)
            # 隧道模式需要端口、域名和 token
            if [[ -z "$ARG_DOMAIN" ]]; then
                log_err "隧道模式需要域名参数 (--domain)"
                exit 1
            fi
            if [[ -z "$ARG_TOKEN" ]]; then
                log_err "隧道模式需要 Token 参数 (--token)"
                exit 1
            fi
            if [[ -n "$ARG_PORT" ]] && ! validate_port "$ARG_PORT"; then
                log_err "端口参数无效"
                exit 1
            fi
            if ! validate_domain "$ARG_DOMAIN"; then
                exit 1
            fi
            ;;
        uninstall)
            # 卸载模式不需要额外参数
            ;;
        manage)
            # 管理模式可以配合 action 使用
            if [[ -n "$ARG_ACTION" ]]; then
                case "$ARG_ACTION" in
                    start|stop|restart|status)
                        ;;
                    *)
                        log_err "无效的操作: $ARG_ACTION (支持: start, stop, restart, status)"
                        exit 1
                        ;;
                esac
            fi
            ;;
        update)
            # 更新模式不需要额外参数
            ;;
        *)
            log_err "无效的模式: $ARG_MODE (支持: direct, tunnel, uninstall, manage, update)"
            exit 1
            ;;
    esac
}

# 检查是否为非交互模式
is_non_interactive() {
    [[ -n "$ARG_MODE" ]]
}

# 静默输出包装
quiet_log() {
    if [[ "$ARG_QUIET" != "true" ]]; then
        "$@"
    fi
}
