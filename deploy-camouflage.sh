#!/bin/bash

# 部署完整的伪装网站 + 隧道
# 在 B 服务器（43.198.243.20）上运行

set -e

echo "🚀 开始部署伪装网站 + 隧道服务器..."

# 1. 安装依赖
echo "📦 安装 Nginx..."
apt update
apt install -y nginx certbot python3-certbot-nginx wget unzip

# 2. 下载真实网站模板（企业官网）
echo "🌐 下载网站模板..."
cd /tmp
wget https://www.free-css.com/assets/files/free-css-templates/download/page296/oxer.zip -O website.zip 2>/dev/null || \
wget https://html5up.net/phantom/download -O website.zip

unzip -o website.zip -d /var/www/html/
chmod -R 755 /var/www/html/

# 如果没有 index.html，创建一个
if [ ! -f /var/www/html/index.html ]; then
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Digital Solutions Company</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
        }
        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 100px 20px;
            text-align: center;
        }
        h1 { font-size: 3em; margin-bottom: 20px; }
        .container { max-width: 1200px; margin: 0 auto; padding: 60px 20px; }
        .services { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 30px; }
        .service-card {
            background: #f8f9fa;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .service-card h3 { margin-bottom: 15px; color: #667eea; }
        footer { background: #2d3748; color: white; text-align: center; padding: 40px 20px; }
    </style>
</head>
<body>
    <header>
        <h1>Digital Solutions</h1>
        <p>Innovative Technology for Modern Business</p>
    </header>

    <div class="container">
        <h2 style="text-align: center; margin-bottom: 50px;">Our Services</h2>
        <div class="services">
            <div class="service-card">
                <h3>🚀 Cloud Infrastructure</h3>
                <p>Scalable and reliable cloud solutions for your business needs.</p>
            </div>
            <div class="service-card">
                <h3>🔒 Cybersecurity</h3>
                <p>Protect your data with enterprise-grade security solutions.</p>
            </div>
            <div class="service-card">
                <h3>📊 Data Analytics</h3>
                <p>Transform your data into actionable business insights.</p>
            </div>
            <div class="service-card">
                <h3>🤖 AI Solutions</h3>
                <p>Leverage artificial intelligence to automate and optimize.</p>
            </div>
            <div class="service-card">
                <h3>📱 Mobile Development</h3>
                <p>Native and cross-platform mobile applications.</p>
            </div>
            <div class="service-card">
                <h3>🌐 Web Development</h3>
                <p>Modern, responsive web applications and websites.</p>
            </div>
        </div>
    </div>

    <footer>
        <p>&copy; 2026 Digital Solutions. All rights reserved.</p>
        <p>contact@digitalsolutions.example</p>
    </footer>
</body>
</html>
EOF
fi

# 3. 配置 Nginx
echo "⚙️  配置 Nginx..."
cat > /etc/nginx/sites-available/default <<'NGINX_EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html index.htm;

    # 正常访问返回真实网站
    location / {
        try_files $uri $uri/ =404;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
    }

    # 隧道路径（需要正确的密码头）
    location /mm {
        # 只转发到本地隧道
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    # 常见扫描路径返回 404
    location ~* ^/(admin|phpmyadmin|wp-admin|wp-login|login|api|.env|backup|config|database) {
        return 404;
    }

    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
    }
}
NGINX_EOF

# 4. 测试并重启 Nginx
nginx -t
systemctl restart nginx
systemctl enable nginx

# 5. 下载隧道服务器
echo "📥 下载隧道服务器..."
cd /root
wget -q https://github.com/acc66/ws-tunnel/releases/download/v1.0.3/ws-tunnel-server-tcp-linux-amd64
chmod +x ws-tunnel-server-tcp-linux-amd64

# 6. 创建 systemd 服务
echo "⚙️  配置 systemd 服务..."
cat > /etc/systemd/system/ws-tunnel.service <<'SERVICE_EOF'
[Unit]
Description=WebSocket TCP Tunnel Server
After=network.target nginx.service

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/root/ws-tunnel-server-tcp-linux-amd64 -listen 127.0.0.1:8080 -path /mm -target 43.198.243.20:20001 -password "66880"
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable ws-tunnel
systemctl start ws-tunnel

# 7. 防火墙配置
echo "🔥 配置防火墙..."
if command -v ufw &> /dev/null; then
    ufw allow 80/tcp
    ufw allow 443/tcp
    echo "y" | ufw enable || true
fi

# 8. 显示状态
echo ""
echo "✅ 部署完成！"
echo ""
echo "📊 服务状态："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
systemctl status nginx --no-pager -l || true
echo ""
systemctl status ws-tunnel --no-pager -l || true
echo ""
echo "🌐 伪装网站测试："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "curl http://43.198.243.20/"
echo ""
echo "🔒 隧道路径（外部扫描返回 401）："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "curl http://43.198.243.20/mm"
echo ""
echo "📱 A 服务器客户端命令（不变）："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "./ws-tunnel-client-linux-amd64 -local 0.0.0.0:1080 -server ws://43.198.243.20/mm -password \"66880\""
echo ""
