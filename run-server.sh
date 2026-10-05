#!/bin/bash
# B 服务器启动脚本 - 开箱即用

# ============ 配置参数（修改这里）============
LISTEN_PORT="8080"              # B 服务器监听端口
WS_PATH="/mm"                   # WebSocket 路径
HAPROXY_IP="3.3.3.3"           # C 服务器 HAProxy IP
HAPROXY_PORT="20001"           # C 服务器 HAProxy 端口
PASSWORD="change_me_to_random_password"  # 连接密码（重要！）
# ==========================================

echo "================================================"
echo "  WebSocket 隧道服务器"
echo "================================================"
echo "监听端口: ${LISTEN_PORT}"
echo "WebSocket 路径: ${WS_PATH}"
echo "转发到: ${HAPROXY_IP}:${HAPROXY_PORT}"
echo "密码: ${PASSWORD}"
echo "================================================"
echo ""

# 检查可执行文件
if [ -f "./bin/ws-tunnel-server-linux" ]; then
    SERVER_BIN="./bin/ws-tunnel-server-linux"
elif [ -f "./ws-tunnel-server-linux" ]; then
    SERVER_BIN="./ws-tunnel-server-linux"
elif [ -f "./ws-tunnel-haproxy" ]; then
    SERVER_BIN="./ws-tunnel-haproxy"
else
    echo "❌ 错误: 找不到服务端可执行文件"
    echo "请先运行: ./build.sh"
    exit 1
fi

echo "🚀 启动服务器..."
echo ""

# 运行服务器
${SERVER_BIN} \
    -listen :${LISTEN_PORT} \
    -path ${WS_PATH} \
    -haproxy-ip ${HAPROXY_IP} \
    -haproxy-port ${HAPROXY_PORT} \
    -password "${PASSWORD}"
