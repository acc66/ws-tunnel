#!/bin/bash
# B 服务器（2.2.2.2）WebSocket 隧道中转部署脚本

set -e

DOMAIN="your-domain.com"  # 修改为你的域名
C_SERVER="3.3.3.3"        # C 服务器 IP
C_PORT="20001"            # C 服务器 HAProxy 端口

echo "=== WebSocket 隧道中转服务器部署 ==="

# 1. 更新系统
apt update && apt upgrade -y

# 2. 安装 Nginx
apt install -y nginx certbot python3-certbot-nginx

# 3. 申请 SSL 证书
echo "申请 SSL 证书（需要域名已解析到当前服务器）..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN || true

# 4. 创建伪装网站
mkdir -p /var/www/html
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Welcome</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>Welcome to Our Service</h1>
    <p>This is a legitimate web service.</p>
</body>
</html>
EOF

# 5. 配置 Nginx
cat > /etc/nginx/sites-available/ws-tunnel <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # 日志
    access_log /var/log/nginx/ws-tunnel-access.log;
    error_log /var/log/nginx/ws-tunnel-error.log;

    # 伪装首页
    location / {
        root /var/www/html;
        index index.html;
    }

    # WebSocket 隧道（关键配置）
    location /mm {
        proxy_pass http://$C_SERVER:$C_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        proxy_connect_timeout 60s;
        proxy_send_timeout 1h;
        proxy_read_timeout 1h;
        proxy_buffering off;
    }
}
EOF

# 6. 启用配置
ln -sf /etc/nginx/sites-available/ws-tunnel /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 7. 测试并重启 Nginx
nginx -t
systemctl restart nginx
systemctl enable nginx

# 8. 防火墙配置
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==================================="
echo "部署完成！"
echo "==================================="
echo "域名: https://$DOMAIN"
echo "WebSocket 路径: wss://$DOMAIN/mm"
echo "转发目标: $C_SERVER:$C_PORT"
echo ""
echo "客户端配置示例："
echo "地址: $DOMAIN"
echo "端口: 443"
echo "路径: /mm"
echo "TLS: 启用"
echo ""
echo "测试访问: curl https://$DOMAIN"
