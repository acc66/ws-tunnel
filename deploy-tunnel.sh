#!/bin/bash
# WebSocket 隧道一键部署脚本

set -e

echo "====================================="
echo "  WebSocket 隧道部署脚本"
echo "====================================="
echo ""

# 检测部署模式
echo "请选择部署模式："
echo "1) 服务端（B 服务器 - 中转服务器）"
echo "2) 客户端（A 服务器 - 源服务器）"
read -p "请输入选项 [1/2]: " DEPLOY_MODE

if [ "$DEPLOY_MODE" == "1" ]; then
    echo ""
    echo "=== 服务端部署 ==="

    # 输入参数
    read -p "监听端口 [8080]: " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-8080}

    read -p "WebSocket 路径 [/mm]: " WS_PATH
    WS_PATH=${WS_PATH:-/mm}

    read -p "目标服务器地址（C 服务器）[3.3.3.3:20001]: " TARGET_ADDR
    TARGET_ADDR=${TARGET_ADDR:-3.3.3.3:20001}

    read -p "连接密码（留空自动生成）: " PASSWORD
    if [ -z "$PASSWORD" ]; then
        PASSWORD=$(openssl rand -base64 32)
        echo "已生成随机密码: $PASSWORD"
    fi

    # 编译
    echo ""
    echo "🔨 编译服务端..."
    if [ ! -f "ws-tunnel-server.go" ]; then
        echo "错误: 找不到 ws-tunnel-server.go"
        exit 1
    fi

    go build -o ws-tunnel-server ws-tunnel-server.go

    # 安装到系统
    echo "📦 安装到系统..."
    sudo cp ws-tunnel-server /usr/local/bin/
    sudo chmod +x /usr/local/bin/ws-tunnel-server

    # 创建 systemd 服务
    echo "⚙️  创建 systemd 服务..."
    sudo tee /etc/systemd/system/ws-tunnel.service > /dev/null <<EOF
[Unit]
Description=WebSocket Tunnel Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ws-tunnel-server -listen :${LISTEN_PORT} -path ${WS_PATH} -target ${TARGET_ADDR} -password ${PASSWORD}
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
    sudo systemctl enable ws-tunnel
    sudo systemctl start ws-tunnel

    # 配置防火墙
    if command -v ufw &> /dev/null; then
        echo "🔥 配置防火墙..."
        sudo ufw allow ${LISTEN_PORT}/tcp
    fi

    echo ""
    echo "====================================="
    echo "✅ 服务端部署完成！"
    echo "====================================="
    echo "监听地址: 0.0.0.0:${LISTEN_PORT}"
    echo "WebSocket 路径: ${WS_PATH}"
    echo "目标服务器: ${TARGET_ADDR}"
    echo "连接密码: ${PASSWORD}"
    echo ""
    echo "客户端连接地址: ws://$(curl -s ifconfig.me):${LISTEN_PORT}${WS_PATH}"
    echo ""
    echo "查看状态: sudo systemctl status ws-tunnel"
    echo "查看日志: sudo journalctl -u ws-tunnel -f"
    echo ""
    echo "⚠️  请保存好上述密码！"

elif [ "$DEPLOY_MODE" == "2" ]; then
    echo ""
    echo "=== 客户端部署 ==="

    # 输入参数
    read -p "本地监听地址 [127.0.0.1:1080]: " LOCAL_ADDR
    LOCAL_ADDR=${LOCAL_ADDR:-127.0.0.1:1080}

    read -p "服务器地址（ws://或wss://）: " SERVER_ADDR
    if [ -z "$SERVER_ADDR" ]; then
        echo "错误: 必须提供服务器地址"
        exit 1
    fi

    read -p "连接密码: " PASSWORD
    if [ -z "$PASSWORD" ]; then
        echo "错误: 必须提供密码"
        exit 1
    fi

    read -p "使用 TLS (wss://)? [y/N]: " USE_TLS
    TLS_FLAG=""
    if [[ "$USE_TLS" =~ ^[Yy]$ ]]; then
        TLS_FLAG="-tls"
    fi

    # 编译
    echo ""
    echo "🔨 编译客户端..."
    if [ ! -f "ws-tunnel-client.go" ]; then
        echo "错误: 找不到 ws-tunnel-client.go"
        exit 1
    fi

    go build -o ws-tunnel-client ws-tunnel-client.go

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
ExecStart=/usr/local/bin/ws-tunnel-client -local ${LOCAL_ADDR} -server ${SERVER_ADDR} -password ${PASSWORD} ${TLS_FLAG}
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

    echo ""
    echo "====================================="
    echo "✅ 客户端部署完成！"
    echo "====================================="
    echo "本地监听: ${LOCAL_ADDR}"
    echo "服务器: ${SERVER_ADDR}"
    echo ""
    echo "测试连接: telnet $(echo ${LOCAL_ADDR} | cut -d: -f1) $(echo ${LOCAL_ADDR} | cut -d: -f2)"
    echo ""
    echo "查看状态: sudo systemctl status ws-tunnel-client"
    echo "查看日志: sudo journalctl -u ws-tunnel-client -f"

else
    echo "无效选项"
    exit 1
fi

echo ""
echo "====================================="
