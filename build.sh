#!/bin/bash
# 一键编译脚本 - 生成 Linux 和 Windows 可执行文件

set -e

echo "================================================"
echo "  WebSocket 隧道编译脚本"
echo "================================================"
echo ""

# 检查 Go 是否安装
if ! command -v go &> /dev/null; then
    echo "❌ 错误: 未安装 Go"
    echo ""
    echo "请先安装 Go:"
    echo "  wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz"
    echo "  tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz"
    echo "  export PATH=\$PATH:/usr/local/go/bin"
    exit 1
fi

echo "✅ Go 版本: $(go version)"
echo ""

# 安装依赖
echo "📦 下载依赖..."
go mod download
echo ""

# 创建输出目录
mkdir -p bin

# 编译服务端 (B 服务器用)
echo "🔨 编译服务端..."
echo "  - Linux 64位"
GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o bin/ws-tunnel-server-linux ws-tunnel-to-haproxy.go
echo "  - Windows 64位"
GOOS=windows GOARCH=amd64 go build -ldflags="-s -w" -o bin/ws-tunnel-server-windows.exe ws-tunnel-to-haproxy.go
echo ""

# 编译客户端 (A 服务器用)
echo "🔨 编译客户端..."
echo "  - Linux 64位"
GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o bin/ws-tunnel-client-linux ws-tunnel-client.go
echo "  - Windows 64位"
GOOS=windows GOARCH=amd64 go build -ldflags="-s -w" -o bin/ws-tunnel-client-windows.exe ws-tunnel-client.go
echo ""

# 设置执行权限
chmod +x bin/ws-tunnel-*-linux

# 文件大小
echo "📊 编译结果:"
ls -lh bin/
echo ""

echo "================================================"
echo "✅ 编译完成！"
echo "================================================"
echo ""
echo "生成的文件:"
echo "  bin/ws-tunnel-server-linux          (B 服务器 - Linux)"
echo "  bin/ws-tunnel-server-windows.exe    (B 服务器 - Windows)"
echo "  bin/ws-tunnel-client-linux          (A 服务器 - Linux)"
echo "  bin/ws-tunnel-client-windows.exe    (A 服务器 - Windows)"
echo ""
echo "使用方法:"
echo ""
echo "【B 服务器】直接运行："
echo "  ./bin/ws-tunnel-server-linux -listen :8080 -path /mm -haproxy-ip 3.3.3.3 -haproxy-port 20001 -password your_password"
echo ""
echo "【A 服务器】直接运行："
echo "  ./bin/ws-tunnel-client-linux -local 127.0.0.1:1080 -server ws://2.2.2.2:8080/mm -password your_password"
echo ""
echo "================================================"
