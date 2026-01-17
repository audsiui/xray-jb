#!/bin/bash

# 参数: $1=服务名, $2=执行命令, $3=参数, $4=日志文件名(可选)
setup_service() {
    local service_name=$1
    local cmd=$2
    local args=$3
    local log_file="${4:-${service_name}.log}"
    local log_path="${LOG_DIR}/${log_file}"

    # 初始化日志目录并轮转旧日志
    init_log_dir
    rotate_log "$log_path"

    log_info "配置服务: ${service_name}..."
    log_info "日志文件: ${log_path}"

    # ---> Systemd (Debian/Ubuntu/CentOS)
    if command -v systemctl >/dev/null; then
        cat > /etc/systemd/system/${service_name}.service <<EOF
[Unit]
Description=${service_name} Service
After=network.target

[Service]
Type=simple
ExecStart=${cmd} ${args}
Restart=on-failure
RestartSec=5s
StandardOutput=append:${log_path}
StandardError=append:${log_path}

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ${service_name} >/dev/null 2>&1
        systemctl restart ${service_name}

    # ---> OpenRC (Alpine)
    elif [ -d "/etc/init.d" ]; then
        if [[ "$OS_TYPE" == "alpine" ]]; then apk add openrc >/dev/null 2>&1; fi

        cat > /etc/init.d/${service_name} <<EOF
#!/sbin/openrc-run
name="${service_name}"
command="${cmd}"
command_args="${args}"
command_background=true
pidfile="/run/${service_name}.pid"
output_log="${log_path}"
error_log="${log_path}"
EOF
        chmod +x /etc/init.d/${service_name}
        rc-update add ${service_name} default
        rc-service ${service_name} restart
    fi
}

# 参数: $1=服务名
remove_service() {
    local service_name=$1

    # Systemd
    if command -v systemctl >/dev/null; then
        systemctl stop ${service_name} >/dev/null 2>&1
        systemctl disable ${service_name} >/dev/null 2>&1
        rm -f /etc/systemd/system/${service_name}.service
    fi

    # OpenRC
    if [ -d "/etc/init.d" ]; then
        rc-service ${service_name} stop >/dev/null 2>&1
        rc-update del ${service_name} >/dev/null 2>&1
        rm -f /etc/init.d/${service_name}
        rm -f /run/${service_name}.pid
    fi
}