#!/bin/bash
# A 服务器客户端启动脚本 - 开箱即用

# ============ 配置参数（修改这里）============
LOCAL_ADDR="127.0.0.1:1080"     # 本地监听地址
SERVER_ADDR="ws://2.2.2.2:8080/mm"  # B 服务器地址
PASSWORD="change_me_to_random_password"  # 连接密码（与 B 服务器相同）
USE_TLS=false                    # 使用 wss:// 改为 true
# ==========================================

echo "================================================"
echo "  WebSocket 隧道客户端"
echo "================================================"
echo "本地监听: ${LOCAL_ADDR}"
echo "服务器: ${SERVER_ADDR}"
echo "密码: ${PASSWORD}"
echo "================================================"
echo ""

# 检查可执行文件
if [ -f "./bin/ws-tunnel-client-linux" ]; then
    CLIENT_BIN="./bin/ws-tunnel-client-linux"
elif [ -f "./ws-tunnel-client-linux" ]; then
    CLIENT_BIN="./ws-tunnel-client-linux"
elif [ -f "./ws-tunnel-client" ]; then
    CLIENT_BIN="./ws-tunnel-client"
else
    echo "❌ 错误: 找不到客户端可执行文件"
    echo "请先运行: ./build.sh"
    exit 1
fi

echo "🚀 启动客户端..."
echo ""

# 构建参数
TLS_FLAG=""
if [ "${USE_TLS}" = "true" ]; then
    TLS_FLAG="-tls"
fi

# 运行客户端
${CLIENT_BIN} \
    -local ${LOCAL_ADDR} \
    -server ${SERVER_ADDR} \
    -password "${PASSWORD}" \
    ${TLS_FLAG}
