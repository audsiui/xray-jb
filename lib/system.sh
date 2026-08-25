#!/bin/bash

# 固定的 Xray 版本
# 说明：上游 x25519 等命令的输出格式曾随版本变化（如 v26 起公钥行变为
# "Password (PublicKey):"），钉死版本可避免上游更新导致脚本解析失效。
# 升级此版本时，需同步检查 core/install_reality.sh 中的密钥解析逻辑。
readonly XRAY_VERSION="26.3.27"

check_sys() {
    if command -v apk >/dev/null; then
        export OS_TYPE="alpine"
        export PM="apk"
        # Alpine 最小依赖：bash 运行脚本、curl 下载、CA 证书用于 HTTPS。
        # Xray 为静态链接二进制，无需 libc6-compat/gcompat；
        # unzip/stat/od/awk 等由 busybox 内建 applet 提供，无需额外安装。
        apk add --no-cache bash curl ca-certificates >/dev/null 2>&1
    elif command -v apt >/dev/null; then
        export OS_TYPE="standard"
        export PM="apt"
        apt-get update >/dev/null 2>&1
        apt-get install -y curl unzip ca-certificates >/dev/null 2>&1
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
            export XRAY_DL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip"
            export CF_DL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        aarch64)
            export XRAY_DL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-arm64-v8a.zip"
            export CF_DL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        *)
            log_err "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
}
