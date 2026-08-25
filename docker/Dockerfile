FROM alpine:3.20

# 安装必要依赖（与 lib/system.sh 保持一致；Alpine 的 busybox 自带 unzip）
RUN apk add --no-cache \
    bash \
    curl \
    ca-certificates

# 创建工作目录
WORKDIR /opt/xray-bundle

# 复制文件
COPY entrypoint.sh /entrypoint.sh
COPY config.json.template /opt/xray-bundle/config.json.template

# 下载 Xray 和 cloudflared（Xray 钉死固定版本 v26.3.27，与 lib/system.sh 保持一致）
ARG XRAY_VERSION=26.3.27
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
        x86_64) \
            XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" && \
            CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;; \
        aarch64) \
            XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-arm64-v8a.zip" && \
            CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;; \
        *) \
            echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    echo "Downloading Xray from: $XRAY_URL" && \
    curl -fL -o xray.zip "$XRAY_URL" && \
    unzip -o xray.zip && \
    rm xray.zip && \
    chmod +x xray && \
    echo "Downloading cloudflared from: $CF_URL" && \
    curl -fL -o cloudflared "$CF_URL" && \
    chmod +x cloudflared

# 设置权限
RUN chmod +x /entrypoint.sh

# 健康检查（检查进程是否运行）
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -x xray && pgrep -x cloudflared || exit 1

# 入口点
ENTRYPOINT ["/entrypoint.sh"]
