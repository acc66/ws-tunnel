#!/bin/bash
# 完整的 A → B → C (HAProxy) 隧道部署脚本

set -e

echo "================================================"
echo "  WebSocket 隧道 → HAProxy 完整部署"
echo "================================================"
echo ""
echo "架构说明："
echo "  A (1.1.1.1) → B (2.2.2.2) → C (3.3.3.3 HAProxy)"
echo "  客户端         Go隧道        你的HAProxy配置"
echo ""

# 检测部署模式
echo "请选择部署角色："
echo "1) B 服务器 - 中转隧道（转发到 C 的 HAProxy）"
echo "2) A 服务器 - 客户端（连接到 B）"
read -p "请输入选项 [1/2]: " DEPLOY_MODE

if [ "$DEPLOY_MODE" == "1" ]; then
    echo ""
    echo "=== B 服务器（中转隧道）部署 ==="
    echo ""

    # 输入参数
    read -p "监听端口 [8080]: " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-8080}

    read -p "WebSocket 路径 [/mm]: " WS_PATH
    WS_PATH=${WS_PATH:-/mm}

    read -p "C 服务器 HAProxy IP [3.3.3.3]: " HAPROXY_IP
    HAPROXY_IP=${HAPROXY_IP:-3.3.3.3}

    read -p "C 服务器 HAProxy 端口 [20001]: " HAPROXY_PORT
    HAPROXY_PORT=${HAPROXY_PORT:-20001}

    read -p "连接密码（留空自动生成）: " PASSWORD
    if [ -z "$PASSWORD" ]; then
        PASSWORD=$(openssl rand -base64 32)
        echo "✅ 已生成随机密码: $PASSWORD"
    fi

    # 编译
    echo ""
    echo "🔨 编译 WebSocket 隧道..."
    if [ ! -f "ws-tunnel-to-haproxy.go" ]; then
        echo "错误: 找不到 ws-tunnel-to-haproxy.go"
        exit 1
    fi

    # 安装依赖
    if [ ! -d "vendor" ] && [ ! -f "go.sum" ]; then
        echo "📦 安装 Go 依赖..."
        go mod download
    fi

    GOOS=linux GOARCH=amd64 go build -o ws-tunnel-haproxy ws-tunnel-to-haproxy.go

    # 安装到系统
    echo "📦 安装到系统..."
    sudo cp ws-tunnel-haproxy /usr/local/bin/
    sudo chmod +x /usr/local/bin/ws-tunnel-haproxy

    # 创建 systemd 服务
    echo "⚙️  创建 systemd 服务..."
    sudo tee /etc/systemd/system/ws-tunnel-haproxy.service > /dev/null <<EOF
[Unit]
Description=WebSocket Tunnel to HAProxy
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/bin
ExecStart=/usr/local/bin/ws-tunnel-haproxy \\
    -listen :${LISTEN_PORT} \\
    -path ${WS_PATH} \\
    -haproxy-ip ${HAPROXY_IP} \\
    -haproxy-port ${HAPROXY_PORT} \\
    -password "${PASSWORD}"
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# 性能优化
LimitNOFILE=100000
LimitNPROC=100000

[Install]
WantedBy=multi-user.target
EOF

    # 配置防火墙
    if command -v ufw &> /dev/null; then
        echo "🔥 配置防火墙..."
        sudo ufw allow ${LISTEN_PORT}/tcp
    fi

    # 启动服务
    echo "🚀 启动服务..."
    sudo systemctl daemon-reload
    sudo systemctl enable ws-tunnel-haproxy
    sudo systemctl start ws-tunnel-haproxy

    # 等待服务启动
    sleep 2

    # 检查服务状态
    if sudo systemctl is-active --quiet ws-tunnel-haproxy; then
        echo ""
        echo "================================================"
        echo "✅ B 服务器部署成功！"
        echo "================================================"
        echo "监听地址: 0.0.0.0:${LISTEN_PORT}"
        echo "WebSocket 路径: ${WS_PATH}"
        echo "转发到 HAProxy: ${HAPROXY_IP}:${HAPROXY_PORT}"
        echo "连接密码: ${PASSWORD}"
        echo ""

        # 获取公网 IP
        PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me || echo "unknown")
        if [ "$PUBLIC_IP" != "unknown" ]; then
            echo "🌐 客户端连接地址："
            echo "   ws://${PUBLIC_IP}:${LISTEN_PORT}${WS_PATH}"
            echo "   或"
            echo "   wss://your-domain.com${WS_PATH} (配置 TLS 后)"
        fi

        echo ""
        echo "📊 管理命令："
        echo "  查看状态: sudo systemctl status ws-tunnel-haproxy"
        echo "  查看日志: sudo journalctl -u ws-tunnel-haproxy -f"
        echo "  重启服务: sudo systemctl restart ws-tunnel-haproxy"
        echo "  停止服务: sudo systemctl stop ws-tunnel-haproxy"
        echo ""
        echo "🧪 测试命令："
        echo "  curl http://localhost:${LISTEN_PORT}/"
        echo "  (应返回 nginx 欢迎页)"
        echo ""
        echo "⚠️  请保存好密码，客户端连接时需要！"
        echo "================================================"
    else
        echo ""
        echo "❌ 服务启动失败，查看日志："
        sudo journalctl -u ws-tunnel-haproxy -n 50 --no-pager
        exit 1
    fi

elif [ "$DEPLOY_MODE" == "2" ]; then
    echo ""
    echo "=== A 服务器（客户端）部署 ==="
    echo ""

    # 输入参数
    read -p "本地监听地址 [127.0.0.1:1080]: " LOCAL_ADDR
    LOCAL_ADDR=${LOCAL_ADDR:-127.0.0.1:1080}

    read -p "B 服务器地址（IP 或域名）: " B_SERVER
    if [ -z "$B_SERVER" ]; then
        echo "错误: 必须提供 B 服务器地址"
        exit 1
    fi

    read -p "B 服务器端口 [8080]: " B_PORT
    B_PORT=${B_PORT:-8080}

    read -p "WebSocket 路径 [/mm]: " WS_PATH
    WS_PATH=${WS_PATH:-/mm}

    read -p "使用 TLS (wss://)? [y/N]: " USE_TLS
    if [[ "$USE_TLS" =~ ^[Yy]$ ]]; then
        PROTOCOL="wss"
        TLS_FLAG="-tls"
    else
        PROTOCOL="ws"
        TLS_FLAG=""
    fi

    SERVER_ADDR="${PROTOCOL}://${B_SERVER}:${B_PORT}${WS_PATH}"

    read -p "连接密码: " PASSWORD
    if [ -z "$PASSWORD" ]; then
        echo "错误: 必须提供密码（与 B 服务器相同）"
        exit 1
    fi

    # 编译
    echo ""
    echo "🔨 编译客户端..."
    if [ ! -f "ws-tunnel-client.go" ]; then
        echo "错误: 找不到 ws-tunnel-client.go"
        exit 1
    fi

    # 安装依赖
    if [ ! -d "vendor" ] && [ ! -f "go.sum" ]; then
        echo "📦 安装 Go 依赖..."
        go mod download
    fi

    GOOS=linux GOARCH=amd64 go build -o ws-tunnel-client ws-tunnel-client.go

    # 安装到系统
    echo "📦 安装到系统..."
    sudo cp ws-tunnel-client /usr/local/bin/
    sudo chmod +x /usr/local/bin/ws-tunnel-client

    # 创建 systemd 服务
    echo "⚙️  创建 systemd 服务..."
    sudo tee /etc/systemd/system/ws-tunnel-client.service > /dev/null <<EOF
[Unit]
Description=WebSocket Tunnel Client
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ws-tunnel-client \\
    -local ${LOCAL_ADDR} \\
    -server ${SERVER_ADDR} \\
    -password "${PASSWORD}" \\
    ${TLS_FLAG}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    echo "🚀 启动服务..."
    sudo systemctl daemon-reload
    sudo systemctl enable ws-tunnel-client
    sudo systemctl start ws-tunnel-client

    # 等待服务启动
    sleep 2

    # 检查服务状态
    if sudo systemctl is-active --quiet ws-tunnel-client; then
        echo ""
        echo "================================================"
        echo "✅ A 服务器客户端部署成功！"
        echo "================================================"
        echo "本地监听: ${LOCAL_ADDR}"
        echo "连接服务器: ${SERVER_ADDR}"
        echo ""
        echo "📊 管理命令："
        echo "  查看状态: sudo systemctl status ws-tunnel-client"
        echo "  查看日志: sudo journalctl -u ws-tunnel-client -f"
        echo "  重启服务: sudo systemctl restart ws-tunnel-client"
        echo "  停止服务: sudo systemctl stop ws-tunnel-client"
        echo ""
        echo "🧪 测试连接："
        LOCAL_IP=$(echo ${LOCAL_ADDR} | cut -d: -f1)
        LOCAL_PORT=$(echo ${LOCAL_ADDR} | cut -d: -f2)
        echo "  telnet ${LOCAL_IP} ${LOCAL_PORT}"
        echo ""
        echo "现在流量路径："
        echo "  应用 → ${LOCAL_ADDR} → ${SERVER_ADDR} → C HAProxy → 后端"
        echo "================================================"
    else
        echo ""
        echo "❌ 服务启动失败，查看日志："
        sudo journalctl -u ws-tunnel-client -n 50 --no-pager
        exit 1
    fi

else
    echo "无效选项"
    exit 1
fi

echo ""
