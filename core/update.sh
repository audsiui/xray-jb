#!/bin/bash

# 获取 Xray 最新版本
get_latest_xray_version() {
    local version
    version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+' | head -n 1)
    echo "$version"
}

# 获取当前 Xray 版本
get_current_xray_version() {
    if [[ ! -f "$XRAY_BIN" ]]; then
        echo "未安装"
        return
    fi

    local version
    version=$("$XRAY_BIN" version 2>/dev/null | grep -oP 'Xray\s+\K[0-9.]+' | head -n 1)
    if [[ -z "$version" ]]; then
        echo "未知"
    else
        echo "$version"
    fi
}

# 获取 cloudflared 最新版本
get_latest_cloudflared_version() {
    local version
    version=$(curl -s "https://api.github.com/repos/cloudflare/cloudflared/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+' | head -n 1)
    echo "$version"
}

# 获取当前 cloudflared 版本
get_current_cloudflared_version() {
    if [[ ! -f "$CF_BIN" ]]; then
        echo "未安装"
        return
    fi

    local version
    version=$("$CF_BIN" --version 2>/dev/null | grep -oP 'cloudflared version\s+\K[0-9.]+' | head -n 1)
    if [[ -z "$version" ]]; then
        echo "未知"
    else
        echo "$version"
    fi
}

# 更新 Xray
update_xray() {
    log_info "正在更新 Xray..."

    local current_version latest_version
    current_version=$(get_current_xray_version)
    latest_version=$(get_latest_xray_version)

    log_info "当前版本: ${current_version}"
    log_info "最新版本: ${latest_version}"

    if [[ "$current_version" == "$latest_version" ]]; then
        log_info "Xray 已是最新版本"
        return 0
    fi

    read -p "是否更新到 ${latest_version}? [Y/n]: " update_choice
    update_choice=$(trim "$update_choice")
    if [[ "$update_choice" =~ ^[Nn]$ ]]; then
        log_info "已取消更新"
        return 0
    fi

    # 停止服务
    local mode
    mode=$(get_current_mode)
    if [[ -n "$mode" ]]; then
        log_info "停止服务..."
        if [[ "$mode" == "direct" ]]; then
            do_service_action "stop" "xray-d"
        else
            do_service_action "stop" "xray-t"
        fi
    fi

    # 下载新版本
    check_sys
    get_arch

    XRAY_ZIP="${WORK_DIR}/xray-new.zip"
    if ! download_file "$XRAY_DL" "$XRAY_ZIP"; then
        log_err "下载 Xray 失败"
        # 恢复服务
        if [[ -n "$mode" ]]; then
            if [[ "$mode" == "direct" ]]; then
                do_service_action "start" "xray-d"
            else
                do_service_action "start" "xray-t"
            fi
        fi
        return 1
    fi

    # 备份旧版本
    if [[ -f "$XRAY_BIN" ]]; then
        cp "$XRAY_BIN" "${XRAY_BIN}.bak"
        log_info "已备份旧版本到 ${XRAY_BIN}.bak"
    fi

    # 解压新版本
    if ! unzip_file "$XRAY_ZIP" "$WORK_DIR"; then
        log_err "解压 Xray 失败"
        rm -f "$XRAY_ZIP"
        # 恢复备份
        if [[ -f "${XRAY_BIN}.bak" ]]; then
            mv "${XRAY_BIN}.bak" "$XRAY_BIN"
        fi
        # 恢复服务
        if [[ -n "$mode" ]]; then
            if [[ "$mode" == "direct" ]]; then
                do_service_action "start" "xray-d"
            else
                do_service_action "start" "xray-t"
            fi
        fi
        return 1
    fi

    chmod +x "$XRAY_BIN"
    rm -f "$XRAY_ZIP"
    clean_work_dir "xray" "geoip.dat" "geosite.dat"

    # 启动服务
    if [[ -n "$mode" ]]; then
        log_info "启动服务..."
        if [[ "$mode" == "direct" ]]; then
            do_service_action "start" "xray-d"
        else
            do_service_action "start" "xray-t"
        fi
    fi

    log_info "Xray 更新完成"
}

# 更新 cloudflared
update_cloudflared() {
    log_info "正在更新 cloudflared..."

    local current_version latest_version
    current_version=$(get_current_cloudflared_version)
    latest_version=$(get_latest_cloudflared_version)

    log_info "当前版本: ${current_version}"
    log_info "最新版本: ${latest_version}"

    if [[ "$current_version" == "$latest_version" ]]; then
        log_info "cloudflared 已是最新版本"
        return 0
    fi

    read -p "是否更新到 ${latest_version}? [Y/n]: " update_choice
    update_choice=$(trim "$update_choice")
    if [[ "$update_choice" =~ ^[Nn]$ ]]; then
        log_info "已取消更新"
        return 0
    fi

    # 停止服务
    if [[ -f "/etc/systemd/system/cloudflared-t.service" ]] || [[ -f "/etc/init.d/cloudflared-t" ]]; then
        log_info "停止 cloudflared 服务..."
        do_service_action "stop" "cloudflared-t"
    fi

    # 下载新版本
    check_sys
    get_arch

    if ! download_file "$CF_DL" "${CF_BIN}.new"; then
        log_err "下载 cloudflared 失败"
        return 1
    fi

    # 备份旧版本
    if [[ -f "$CF_BIN" ]]; then
        cp "$CF_BIN" "${CF_BIN}.bak"
        log_info "已备份旧版本到 ${CF_BIN}.bak"
    fi

    # 替换新版本
    mv "${CF_BIN}.new" "$CF_BIN"
    chmod +x "$CF_BIN"

    # 启动服务
    if [[ -f "/etc/systemd/system/cloudflared-t.service" ]] || [[ -f "/etc/init.d/cloudflared-t" ]]; then
        log_info "启动 cloudflared 服务..."
        do_service_action "start" "cloudflared-t"
    fi

    log_info "cloudflared 更新完成"
}

# 更新菜单
run_update() {
    local mode
    mode=$(get_current_mode)

    if [[ -z "$mode" ]]; then
        log_err "未检测到已安装的服务"
        return 1
    fi

    clear
    echo -e "------------------------------------------------"
    echo -e "${GREEN}  更新 Xray/cloudflared${PLAIN}"
    echo -e "------------------------------------------------"

    # 显示当前版本
    local xray_current cf_current
    xray_current=$(get_current_xray_version)
    cf_current=$(get_current_cloudflared_version)

    echo -e "\n当前安装版本:"
    echo "  Xray: ${CYAN}${xray_current}${PLAIN}"
    echo "  cloudflared: ${CYAN}${cf_current}${PLAIN}\n"

    echo -e "${CYAN}请选择要更新的组件:${PLAIN}"
    echo "  1. 更新 Xray"
    echo "  2. 更新 cloudflared"
    echo "  3. 全部更新"
    echo "  0. 返回"
    echo -e "------------------------------------------------"

    read -p "请选择 [0-3]: " choice

    case $choice in
        1)
            update_xray
            read -p "按回车键返回..."
            ;;
        2)
            update_cloudflared
            read -p "按回车键返回..."
            ;;
        3)
            update_xray
            echo ""
            update_cloudflared
            read -p "按回车键返回..."
            ;;
        0)
            return 0
            ;;
        *)
            log_err "无效选项"
            sleep 1
            ;;
    esac
}

# 非交互式更新
run_update_non_interactive() {
    local mode
    mode=$(get_current_mode)

    if [[ -z "$mode" ]]; then
        log_err "未检测到已安装的服务"
        return 1
    fi

    log_info "正在更新所有组件..."

    update_xray
    echo ""
    update_cloudflared
}
