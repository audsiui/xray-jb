#!/bin/bash

check_sys() {
    if command -v apk >/dev/null; then
        export OS_TYPE="alpine"
        export PM="apk"
        # Alpine 兼容性修复 (关键)
        apk add --no-cache bash curl unzip ca-certificates libc6-compat gcompat coreutils >/dev/null 2>&1
    elif command -v apt >/dev/null; then
        export OS_TYPE="standard"
        export PM="apt"
        apt update >/dev/null 2>&1
        apt install -y curl unzip ca-certificates >/dev/null 2>&1
    elif command -v yum >/dev/null; then
        export OS_TYPE="standard"
        export PM="yum"
        yum install -y curl unzip ca-certificates >/dev/null 2>&1
    else
        log_err "不支持的系统包管理器"
        exit 1
    fi
}

get_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  
            export XRAY_DL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
            export CF_DL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        aarch64) 
            export XRAY_DL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
            export CF_DL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        *)       
            log_err "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
}