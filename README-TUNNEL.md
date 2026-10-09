# WebSocket 隧道 - 简单 Go 实现

## 📋 功能特性

- ✅ **路径保护**：只有 `/mm` 路径可访问，其他路径返回伪装的 nginx 页面
- ✅ **密码认证**：通过 HTTP Authorization Header 验证
- ✅ **双向转发**：A 服务器 ↔ B 服务器 ↔ C 服务器
- ✅ **防探测**：非法路径返回伪装 nginx 欢迎页
- ✅ **高性能**：使用 goroutine 并发处理，支持大量连接
- ✅ **简单部署**：单个二进制文件，无需依赖

---

## 🏗️ 架构说明

```
A 服务器 (1.1.1.1)          B 服务器 (2.2.2.2)           C 服务器 (3.3.3.3)
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│                 │         │                  │         │                 │
│  ws-tunnel-     │  WSS    │  ws-tunnel-      │  TCP    │   HAProxy       │
│  client         │────────>│  server          │────────>│   后端服务      │
│  (客户端)       │  /mm    │  (服务端)        │  转发   │                 │
│                 │  密码    │                  │         │                 │
└─────────────────┘         └──────────────────┘         └─────────────────┘
   本地监听 1080               监听 8080                    你的现有配置
```

---

## 🚀 快速开始

### 1. 编译

```bash
# 安装依赖
go mod download

# 编译服务端和客户端
make all

# 或者分别编译
make server
make client

# 交叉编译 Linux 版本
make linux
```

### 2. B 服务器部署（2.2.2.2）

```bash
# 上传编译好的 ws-tunnel-server 到服务器

# 运行（前台测试）
./ws-tunnel-server \
  -listen :8080 \
  -path /mm \
  -target 3.3.3.3:20001 \
  -password your_secret_password

# 后台运行（推荐使用 systemd）
```

#### Systemd 服务配置（B 服务器）

```bash
# 创建服务文件
sudo tee /etc/systemd/system/ws-tunnel.service > /dev/null <<EOF
[Unit]
Description=WebSocket Tunnel Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ws-tunnel-server -listen :8080 -path /mm -target 3.3.3.3:20001 -password your_secret_password
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
sudo systemctl daemon-reload
sudo systemctl enable ws-tunnel
sudo systemctl start ws-tunnel

# 查看状态
sudo systemctl status ws-tunnel

# 查看日志
sudo journalctl -u ws-tunnel -f
```

### 3. A 服务器部署（1.1.1.1）

```bash
# 运行客户端
./ws-tunnel-client \
  -local 127.0.0.1:1080 \
  -server ws://2.2.2.2:8080/mm \
  -password your_secret_password

# 使用 TLS (WSS)
./ws-tunnel-client \
  -local 127.0.0.1:1080 \
  -server wss://your-domain.com/mm \
  -password your_secret_password \
  -tls
```

---

## 🔧 参数说明

### 服务端（ws-tunnel-server）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-listen` | `:8080` | WebSocket 监听地址 |
| `-path` | `/mm` | WebSocket 路径（只有此路径可访问） |
| `-target` | `3.3.3.3:20001` | 转发目标地址（C 服务器） |
| `-password` | `your_secret_password` | 连接密码 |

### 客户端（ws-tunnel-client）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-local` | `127.0.0.1:1080` | 本地监听地址 |
| `-server` | `ws://2.2.2.2:8080/mm` | WebSocket 服务器地址 |
| `-password` | `your_secret_password` | 连接密码 |
| `-tls` | `false` | 使用 WSS (TLS) |

---

## 🔒 配合 TLS/HTTPS 使用

### 方法 1：Nginx 反向代理（推荐）

B 服务器使用 Nginx 做 TLS 终止：

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    # 伪装首页
    location / {
        return 200 "Welcome to nginx!";
    }

    # WebSocket 隧道
    location /mm {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

客户端连接：
```bash
./ws-tunnel-client \
  -local 127.0.0.1:1080 \
  -server wss://your-domain.com/mm \
  -password your_secret_password \
  -tls
```

### 方法 2：直接在 Go 程序中启用 TLS

修改服务端代码，使用 `http.ListenAndServeTLS()` 即可。

---

## 🧪 测试验证

### 测试服务端

```bash
# 1. 测试伪装页面（应该返回 nginx 欢迎页）
curl http://2.2.2.2:8080/

# 2. 测试非法路径（应该返回 nginx 欢迎页）
curl http://2.2.2.2:8080/test

# 3. 测试 WebSocket 路径（需要密码，无密码应该返回 401）
curl -i http://2.2.2.2:8080/mm
```

### 测试客户端连接

```bash
# 启动客户端后，测试本地端口
telnet 127.0.0.1 1080

# 或者通过本地端口访问 C 服务器
curl --proxy socks5://127.0.0.1:1080 http://example.com
```

---

## 📊 性能优化

### 系统参数调整

```bash
# 增加文件描述符限制
ulimit -n 100000

# /etc/sysctl.conf 添加
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65535

# 应用配置
sysctl -p
```

### Go 程序优化

代码中已包含的优化：
- 64KB 读写缓冲区
- 并发处理连接
- 优雅的错误处理

---

## 🛡️ 安全建议

1. **修改默认密码**：使用强密码（32 位以上随机字符串）
   ```bash
   # 生成随机密码
   openssl rand -base64 32
   ```

2. **使用 TLS**：生产环境必须使用 HTTPS/WSS

3. **防火墙配置**：
   ```bash
   # B 服务器只开放必要端口
   ufw allow 8080/tcp
   ufw allow 443/tcp
   ufw enable
   ```

4. **IP 白名单**（可选）：
   修改 `ws-tunnel-server.go`，在 `handleWebSocket` 中添加 IP 验证：
   ```go
   allowedIPs := []string{"1.1.1.1"}
   clientIP := r.RemoteAddr
   // 验证逻辑...
   ```

---

## 📝 日志示例

**服务端日志：**
```
🚀 WebSocket 隧道服务器启动
📍 监听地址: :8080
🔑 WebSocket 路径: /mm
🎯 转发目标: 3.3.3.3:20001
⚠️  其他路径将返回伪装页面
✅ 新连接: 1.1.1.1:54321
🔗 已连接目标: 3.3.3.3:20001
🔌 连接关闭: 1.1.1.1:54321
```

**客户端日志：**
```
🚀 WebSocket 隧道客户端启动
📍 本地监听: 127.0.0.1:1080
🌐 服务器: ws://2.2.2.2:8080/mm
✅ 等待连接...
✅ 新本地连接: 127.0.0.1:12345
🔗 已连接服务器: ws://2.2.2.2:8080/mm
🔌 连接关闭: 127.0.0.1:12345
```

---

## 🐛 故障排查

### 连接失败

1. 检查防火墙是否开放端口
2. 确认密码是否一致
3. 查看服务端日志：`journalctl -u ws-tunnel -f`

### 性能问题

1. 检查网络延迟：`ping 2.2.2.2`
2. 检查带宽：`iperf3 -c 2.2.2.2`
3. 增加系统文件描述符限制

### WebSocket 升级失败

1. 确认中间没有不支持 WebSocket 的代理
2. 检查 Nginx 配置是否正确设置 Upgrade 头

---

## 📦 编译的二进制文件

运行 `make all` 后生成：
- `ws-tunnel-server` - 服务端（部署到 B 服务器）
- `ws-tunnel-client` - 客户端（部署到 A 服务器）

运行 `make linux` 后额外生成：
- `ws-tunnel-server-linux` - Linux 服务端
- `ws-tunnel-client-linux` - Linux 客户端

---

## 🔗 配合现有 HAProxy 使用

你的 C 服务器 HAProxy 配置保持不变，只需确保：

1. B 服务器的 `-target` 参数指向 C 服务器的正确端口
2. C 服务器的 HAProxy 允许 B 服务器的 IP 访问

示例：
```bash
# B 服务器启动命令
./ws-tunnel-server \
  -listen :8080 \
  -path /mm \
  -target 3.3.3.3:20001 \
  -password $(openssl rand -base64 32)
```

---

## 📄 许可证

MIT License - 自由使用和修改
