#!/bin/bash
# 全平台编译脚本 - Linux, Windows, macOS, ARM

set -e

VERSION="v1.0.0"
BUILD_TIME=$(date -u +"%Y-%m-%d_%H:%M:%S_UTC")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

echo "================================================"
echo "  WebSocket 隧道 - 全平台编译"
echo "  版本: ${VERSION}"
echo "================================================"
echo ""

# 安装依赖
echo "📦 下载依赖..."
go mod download
echo ""

# 创建输出目录
rm -rf releases
mkdir -p releases

# 构建标志
LDFLAGS="-s -w -X main.Version=${VERSION} -X main.BuildTime=${BUILD_TIME} -X main.GitCommit=${GIT_COMMIT}"

# 编译函数
build() {
    local GOOS=$1
    local GOARCH=$2
    local OUTPUT=$3
    local SOURCE=$4

    echo "🔨 编译 ${OUTPUT}..."
    GOOS=${GOOS} GOARCH=${GOARCH} go build -ldflags="${LDFLAGS}" -o releases/${OUTPUT} ${SOURCE}
}

echo "开始编译..."
echo ""

# 服务端 (B 服务器用)
echo "=== 编译服务端 (ws-tunnel-server) ==="
build linux amd64 ws-tunnel-server-linux-amd64 ws-tunnel-to-haproxy.go
build linux arm64 ws-tunnel-server-linux-arm64 ws-tunnel-to-haproxy.go
build linux 386 ws-tunnel-server-linux-386 ws-tunnel-to-haproxy.go
build windows amd64 ws-tunnel-server-windows-amd64.exe ws-tunnel-to-haproxy.go
build windows 386 ws-tunnel-server-windows-386.exe ws-tunnel-to-haproxy.go
build darwin amd64 ws-tunnel-server-darwin-amd64 ws-tunnel-to-haproxy.go
build darwin arm64 ws-tunnel-server-darwin-arm64 ws-tunnel-to-haproxy.go
echo ""

# 客户端 (A 服务器用)
echo "=== 编译客户端 (ws-tunnel-client) ==="
build linux amd64 ws-tunnel-client-linux-amd64 ws-tunnel-client.go
build linux arm64 ws-tunnel-client-linux-arm64 ws-tunnel-client.go
build linux 386 ws-tunnel-client-linux-386 ws-tunnel-client.go
build windows amd64 ws-tunnel-client-windows-amd64.exe ws-tunnel-client.go
build windows 386 ws-tunnel-client-windows-386.exe ws-tunnel-client.go
build darwin amd64 ws-tunnel-client-darwin-amd64 ws-tunnel-client.go
build darwin arm64 ws-tunnel-client-darwin-arm64 ws-tunnel-client.go
echo ""

# 设置执行权限
chmod +x releases/ws-tunnel-*-linux-* releases/ws-tunnel-*-darwin-*

# 复制配置文件
echo "📄 复制配置文件..."
cp run-server.sh releases/
cp run-client.sh releases/
cp QUICK-START.md releases/
cp README-COMPLETE.md releases/
echo ""

# 生成校验和
echo "🔐 生成 SHA256 校验和..."
cd releases
sha256sum ws-tunnel-* > SHA256SUMS
cd ..
echo ""

# 显示结果
echo "================================================"
echo "✅ 编译完成！"
echo "================================================"
echo ""
echo "生成的文件:"
ls -lh releases/ | grep -v total
echo ""
echo "文件位置: ./releases/"
echo ""
echo "平台支持:"
echo "  - Linux (x64, ARM64, x86)"
echo "  - Windows (x64, x86)"
echo "  - macOS (Intel, Apple Silicon)"
echo ""
