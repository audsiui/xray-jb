#!/bin/bash

# 参数: $1=服务名, $2=执行命令, $3=参数
setup_service() {
    local service_name=$1
    local cmd=$2
    local args=$3
    
    log_info "配置服务: ${service_name}..."

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
    fi
}