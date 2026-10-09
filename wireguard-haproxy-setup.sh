#!/bin/bash
# B 服务器（2.2.2.2）完整部署脚本

set -e

echo "=== WireGuard + HAProxy 隧道部署 ==="

# 1. 安装依赖
apt update
apt install -y wireguard haproxy iptables-persistent

# 2. 生成 WireGuard 密钥
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
chmod 600 /etc/wireguard/server_private.key

SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key)
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)

# 3. 创建 WireGuard 配置
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# A 服务器配置（需要 A 服务器的公钥）
# [Peer]
# PublicKey = <A服务器公钥>
# AllowedIPs = 10.0.0.2/32
EOF

# 4. 启用 IP 转发
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# 5. 创建 HAProxy 配置
cat > /etc/haproxy/haproxy.cfg <<'EOF'
global
  log 127.0.0.1 local0
  daemon
  nbthread 4
  maxconn 50000

defaults
  log global
  mode tcp
  timeout connect 10s
  timeout client 1h
  timeout server 1h

# 主要转发：WireGuard 流量 → C 服务器
listen tunnel_main
  bind 10.0.0.1:20001
  mode tcp
  balance roundrobin
  server c_server 3.3.3.3:20001 check inter 10s rise 2 fall 3

listen tunnel_58888
  bind 10.0.0.1:58888
  mode tcp
  server c_server 3.3.3.3:58888 check inter 10s

listen tunnel_18888
  bind 10.0.0.1:18888
  mode tcp
  server c_server 3.3.3.3:18888 check inter 10s

# 监控面板
listen stats
  bind 0.0.0.0:22888
  mode http
  stats enable
  stats uri /
  stats auth admin:admin
EOF

# 6. 启动服务
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
systemctl restart haproxy

echo "==================================="
echo "部署完成！"
echo "==================================="
echo "B 服务器公钥（配置到 A 服务器）："
echo "$SERVER_PUBLIC_KEY"
echo ""
echo "A 服务器需要配置："
echo "[Interface]"
echo "PrivateKey = <A服务器生成的私钥>"
echo "Address = 10.0.0.2/24"
echo ""
echo "[Peer]"
echo "PublicKey = $SERVER_PUBLIC_KEY"
echo "Endpoint = 2.2.2.2:51820"
echo "AllowedIPs = 10.0.0.0/24, 3.3.3.3/32"
echo "PersistentKeepalive = 25"
echo ""
echo "A 服务器生成密钥命令："
echo "wg genkey | tee client_private.key | wg pubkey"
echo ""
echo "监控面板: http://2.2.2.2:22888"
