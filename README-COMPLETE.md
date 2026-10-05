# WebSocket 隧道 → HAProxy 完整方案

## 🏗️ 架构图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         完整流量路径                                      │
└─────────────────────────────────────────────────────────────────────────┘

A 服务器 (1.1.1.1)          B 服务器 (2.2.2.2)           C 服务器 (3.3.3.3)
中国国内                     中转节点                      最终服务器
┌──────────────────┐        ┌───────────────────┐        ┌──────────────────┐
│                  │        │                   │        │                  │
│  应用程序        │        │  Go WebSocket     │        │  HAProxy         │
│    ↓             │        │  隧道服务器       │        │  (你的配置)      │
│  ws-tunnel-      │  WSS   │    ↓              │  WS    │    ↓             │
│  client          │───────>│  接收 WebSocket   │───────>│  frontend mmk    │
│  (127.0.0.1:1080)│ 加密   │    ↓              │  转发  │  (路径 /mm)      │
│                  │  密码  │  转发到 HAProxy   │  握手  │    ↓             │
│                  │        │                   │        │  backend 选择    │
│                  │        │                   │        │    ↓             │
│                  │        │                   │        │  后端服务器      │
└──────────────────┘        └───────────────────┘        └──────────────────┘
   防火墙内部                  公网可访问                   防火墙保护
```

---

## 📋 核心特性

### B 服务器（Go 隧道程序）

✅ **路径保护**：只有 `/mm` 可访问，配合你的 HAProxy 配置
✅ **密码认证**：Bearer Token 方式验证
✅ **WebSocket 转发**：完整的 WebSocket 握手转发到 HAProxy
✅ **防探测伪装**：非法路径返回 nginx 欢迎页
✅ **高性能**：Go 协程并发处理，支持大量连接

### C 服务器（HAProxy 配置）

✅ 保持你现有的配置不变
✅ frontend mmk 监听多个端口：20001, 58888, 18888, 88, 77, 28888
✅ 路径验证：只处理 `/mm` 路径的 WebSocket
✅ 反 GFW 探测系统保持生效

---

## 🚀 部署步骤

### 前提条件

```bash
# 所有服务器都需要安装 Go（1.19+）
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc
```

---

### 步骤 1：C 服务器（3.3.3.3）- 保持现有配置

你的 C 服务器 HAProxy 配置已经完美：

```bash
# 确认 HAProxy 正在运行
systemctl status haproxy

# 确认端口监听
ss -tlnp | grep 20001

# 测试路径验证
curl -I http://3.3.3.3:20001/mm
# 应返回 400 或类似错误（因为不是 WebSocket 握手）

curl http://3.3.3.3:20001/
# 应返回 nginx 欢迎页（honeypot）
```

**无需修改任何配置！** ✅

---

### 步骤 2：B 服务器（2.2.2.2）- 部署 Go 隧道

#### 方法 A：一键脚本部署（推荐）

```bash
# 1. 上传文件到 B 服务器
scp ws-tunnel-to-haproxy.go go.mod deploy-complete-tunnel.sh root@2.2.2.2:/root/

# 2. SSH 登录 B 服务器
ssh root@2.2.2.2

# 3. 运行部署脚本
chmod +x deploy-complete-tunnel.sh
./deploy-complete-tunnel.sh

# 4. 选择选项 1（B 服务器 - 中转隧道）
# 按提示输入：
#   - 监听端口: 8080
#   - WebSocket 路径: /mm
#   - C 服务器 HAProxy IP: 3.3.3.3
#   - C 服务器 HAProxy 端口: 20001
#   - 连接密码: (自动生成或手动输入)
```

#### 方法 B：手动部署

```bash
# 1. 编译
go mod download
go build -o ws-tunnel-haproxy ws-tunnel-to-haproxy.go

# 2. 测试运行
./ws-tunnel-haproxy \
  -listen :8080 \
  -path /mm \
  -haproxy-ip 3.3.3.3 \
  -haproxy-port 20001 \
  -password "$(openssl rand -base64 32)"

# 3. 创建 systemd 服务（见部署脚本）
```

#### 验证 B 服务器

```bash
# 测试伪装页面（应返回 nginx 页面）
curl http://localhost:8080/

# 测试非法路径（应返回 nginx 页面）
curl http://localhost:8080/test

# 查看日志
journalctl -u ws-tunnel-haproxy -f
```

---

### 步骤 3：A 服务器（1.1.1.1）- 部署客户端

#### 方法 A：一键脚本部署

```bash
# 1. 上传文件到 A 服务器
scp ws-tunnel-client.go go.mod deploy-complete-tunnel.sh root@1.1.1.1:/root/

# 2. SSH 登录 A 服务器
ssh root@1.1.1.1

# 3. 运行部署脚本
chmod +x deploy-complete-tunnel.sh
./deploy-complete-tunnel.sh

# 4. 选择选项 2（A 服务器 - 客户端）
# 按提示输入：
#   - 本地监听地址: 127.0.0.1:1080
#   - B 服务器地址: 2.2.2.2
#   - B 服务器端口: 8080
#   - WebSocket 路径: /mm
#   - 使用 TLS: n (或 y，如果配置了 HTTPS)
#   - 连接密码: (输入与 B 服务器相同的密码)
```

#### 方法 B：手动部署

```bash
# 编译
go build -o ws-tunnel-client ws-tunnel-client.go

# 运行
./ws-tunnel-client \
  -local 127.0.0.1:1080 \
  -server ws://2.2.2.2:8080/mm \
  -password "你的密码"
```

---

## 🧪 完整测试流程

### 1. 测试 C 服务器 HAProxy

```bash
# 在 C 服务器上
curl http://localhost:20001/
# 应返回 nginx 欢迎页（honeypot 生效）
```

### 2. 测试 B 服务器隧道

```bash
# 在 B 服务器上
curl http://localhost:8080/
# 应返回 nginx 欢迎页（伪装生效）

# 查看运行日志
journalctl -u ws-tunnel-haproxy -f
```

### 3. 测试 A 到 B 的连接

```bash
# 在 A 服务器上
telnet 127.0.0.1 1080
# 应成功连接

# 查看客户端日志
journalctl -u ws-tunnel-client -f
# 应看到 "已连接服务器" 的日志
```

### 4. 端到端测试

```bash
# 在 A 服务器上，通过本地端口测试整个链路
curl --proxy socks5://127.0.0.1:1080 http://example.com

# 或者使用 nc 测试
echo "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n" | nc -v 127.0.0.1 1080
```

### 5. 查看整条链路的日志

```bash
# C 服务器 HAProxy 日志
tail -f /var/log/haproxy.log

# B 服务器 Go 隧道日志
journalctl -u ws-tunnel-haproxy -f

# A 服务器客户端日志
journalctl -u ws-tunnel-client -f
```

---

## 🔒 配合 TLS/HTTPS（强烈推荐）

### 在 B 服务器前加 Nginx

```nginx
# /etc/nginx/sites-available/ws-tunnel

server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    # SSL 证书（Let's Encrypt）
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    # 伪装首页
    location / {
        return 200 "Welcome";
    }

    # WebSocket 隧道
    location /mm {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Authorization $http_authorization;

        proxy_connect_timeout 60s;
        proxy_send_timeout 1h;
        proxy_read_timeout 1h;
    }
}
```

### 申请免费 SSL 证书

```bash
# B 服务器上
apt install certbot python3-certbot-nginx -y
certbot --nginx -d your-domain.com
```

### A 服务器客户端改用 WSS

```bash
# 修改客户端连接为 HTTPS
./ws-tunnel-client \
  -local 127.0.0.1:1080 \
  -server wss://your-domain.com/mm \
  -password "你的密码" \
  -tls
```

---

## 📊 监控和维护

### 性能监控

```bash
# B 服务器连接数
ss -tn | grep :8080 | wc -l

# 进程状态
top -p $(pgrep ws-tunnel-haproxy)

# 网络流量
iftop -i eth0
```

### 日志管理

```bash
# 限制日志大小
sudo journalctl --vacuum-size=100M

# 只保留最近 7 天
sudo journalctl --vacuum-time=7d
```

---

## 🐛 故障排查

### 问题 1：B 服务器无法连接 C 服务器

```bash
# 检查网络连通性
ping 3.3.3.3
telnet 3.3.3.3 20001

# 检查 C 服务器防火墙
# 在 C 服务器上允许 B 的 IP
ufw allow from 2.2.2.2 to any port 20001
```

### 问题 2：A 服务器连接 B 失败

```bash
# 检查 B 服务器防火墙
ufw status
ufw allow 8080/tcp

# 检查服务是否运行
systemctl status ws-tunnel-haproxy

# 查看详细日志
journalctl -u ws-tunnel-haproxy -n 100 --no-pager
```

### 问题 3：WebSocket 握手失败

```bash
# B 服务器日志应显示：
# ✅ HAProxy WebSocket 握手成功

# 如果失败，检查：
# 1. C 服务器 HAProxy 是否正确处理 /mm 路径
# 2. 查看 C 服务器 HAProxy 日志
tail -f /var/log/haproxy.log

# 3. 手动测试 C 服务器
wscat -c ws://3.3.3.3:20001/mm
```

### 问题 4：密码认证失败

```bash
# 确保 A 和 B 使用相同的密码
# 查看 B 服务器配置
systemctl cat ws-tunnel-haproxy | grep password

# 重新设置密码
sudo systemctl stop ws-tunnel-haproxy
# 编辑 /etc/systemd/system/ws-tunnel-haproxy.service
sudo systemctl daemon-reload
sudo systemctl start ws-tunnel-haproxy
```

---

## 🎯 完整流量路径示例

```
1. 用户应用 → 127.0.0.1:1080 (A 服务器本地)
   ↓
2. ws-tunnel-client → ws://2.2.2.2:8080/mm (A → B WebSocket)
   ↓ 加密 + 密码验证
3. ws-tunnel-haproxy 接收 (B 服务器)
   ↓ 验证路径 /mm + 密码
4. 转发 WebSocket 握手 → 3.3.3.3:20001/mm
   ↓
5. HAProxy frontend mmk (C 服务器)
   ↓ 验证路径 /mm + WebSocket 头
6. HAProxy backend 选择
   ↓
7. 最终后端服务器
```

---

## 💡 优化建议

### 1. 使用 Cloudflare CDN（最强抗封锁）

```
A → Cloudflare CDN → B (Nginx+TLS) → Go隧道 → C (HAProxy)
```

### 2. 多端口部署（负载均衡）

```bash
# B 服务器运行多个实例
# 端口 8080 → C:20001
# 端口 8081 → C:58888
# 端口 8082 → C:18888
```

### 3. 自动重连（客户端）

客户端代码已内置 `Restart=always`，网络断开会自动重连。

---

## 📄 配置文件清单

### B 服务器文件

```
/usr/local/bin/ws-tunnel-haproxy          # 主程序
/etc/systemd/system/ws-tunnel-haproxy.service  # 服务配置
```

### A 服务器文件

```
/usr/local/bin/ws-tunnel-client           # 客户端程序
/etc/systemd/system/ws-tunnel-client.service   # 服务配置
```

### C 服务器文件

```
/etc/haproxy/haproxy.cfg                  # 你现有的配置（无需修改）
```

---

## ✅ 验收检查清单

- [ ] C 服务器 HAProxy 正常运行
- [ ] B 服务器 Go 隧道正常运行
- [ ] A 服务器客户端正常运行
- [ ] 测试访问伪装页面返回 nginx 欢迎页
- [ ] 端到端流量可以通过
- [ ] 日志显示连接正常
- [ ] 配置了 systemd 自动启动
- [ ] （可选）配置了 TLS/HTTPS

---

## 🔐 安全清单

- [ ] 使用强密码（32 位以上）
- [ ] 修改默认端口
- [ ] 配置防火墙规则
- [ ] 启用 TLS/HTTPS
- [ ] 定期更新系统和程序
- [ ] 监控异常连接

---

完成部署后，整个链路为：

**A (1.1.1.1) → B (2.2.2.2) → C (3.3.3.3 HAProxy) → 后端服务器**

中国国内 IP 通过加密 WebSocket 隧道，穿过 B 服务器中转，最终到达你的 C 服务器 HAProxy，整条链路受密码保护和路径验证保护！
