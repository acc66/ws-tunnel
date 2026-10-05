# 快速开始 - 3 步完成部署

## 📋 准备工作

你需要准备：
- A 服务器（中国国内 IP：1.1.1.1）
- B 服务器（中转节点 IP：2.2.2.2）- 需要安装 Go
- C 服务器（最终服务器 IP：3.3.3.3）- 已有 HAProxy 配置

---

## 🚀 第一步：编译（任意一台有 Go 的机器）

### 如果没有 Go，先安装：

```bash
# Linux 快速安装 Go
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
go version
```

### 编译所有程序：

```bash
# 赋予执行权限
chmod +x build.sh

# 一键编译（生成 Linux 和 Windows 版本）
./build.sh
```

编译完成后，在 `bin/` 目录下会生成：
```
bin/
├── ws-tunnel-server-linux          # B 服务器用（Linux）
├── ws-tunnel-server-windows.exe    # B 服务器用（Windows）
├── ws-tunnel-client-linux          # A 服务器用（Linux）
└── ws-tunnel-client-windows.exe    # A 服务器用（Windows）
```

---

## 🚀 第二步：部署 B 服务器（中转节点）

### 1. 上传文件到 B 服务器

```bash
scp bin/ws-tunnel-server-linux run-server.sh root@2.2.2.2:/root/
```

### 2. SSH 登录 B 服务器

```bash
ssh root@2.2.2.2
```

### 3. 修改配置并运行

```bash
# 赋予执行权限
chmod +x ws-tunnel-server-linux run-server.sh

# 编辑配置（重要！）
nano run-server.sh
```

修改以下参数：
```bash
LISTEN_PORT="8080"              # B 服务器监听端口
WS_PATH="/mm"                   # WebSocket 路径
HAPROXY_IP="3.3.3.3"           # C 服务器 IP（改成你的）
HAPROXY_PORT="20001"           # C 服务器 HAProxy 端口
PASSWORD="你的强密码"           # 生成一个复杂密码
```

生成随机密码：
```bash
openssl rand -base64 32
```

### 4. 运行服务器

```bash
# 前台测试运行
./run-server.sh

# 看到以下信息表示成功：
# 🚀 WebSocket 隧道服务器启动
# 📍 监听地址: :8080
# 🔑 WebSocket 路径: /mm
# 🎯 HAProxy 地址: 3.3.3.3:20001
```

### 5. 后台运行（推荐使用 screen）

```bash
# 安装 screen
apt install screen -y

# 创建会话
screen -S tunnel-server

# 运行服务器
./run-server.sh

# 按 Ctrl+A 然后按 D 退出（程序继续运行）

# 重新连接会话
screen -r tunnel-server
```

### 6. 或者使用 systemd 服务

```bash
sudo tee /etc/systemd/system/ws-tunnel.service > /dev/null <<EOF
[Unit]
Description=WebSocket Tunnel Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/root/ws-tunnel-server-linux -listen :8080 -path /mm -haproxy-ip 3.3.3.3 -haproxy-port 20001 -password "你的密码"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ws-tunnel
sudo systemctl start ws-tunnel
sudo systemctl status ws-tunnel
```

---

## 🚀 第三步：部署 A 服务器（客户端）

### 1. 上传文件到 A 服务器

```bash
scp bin/ws-tunnel-client-linux run-client.sh root@1.1.1.1:/root/
```

### 2. SSH 登录 A 服务器

```bash
ssh root@1.1.1.1
```

### 3. 修改配置并运行

```bash
# 赋予执行权限
chmod +x ws-tunnel-client-linux run-client.sh

# 编辑配置
nano run-client.sh
```

修改以下参数：
```bash
LOCAL_ADDR="127.0.0.1:1080"              # 本地监听地址
SERVER_ADDR="ws://2.2.2.2:8080/mm"      # B 服务器地址（改成你的）
PASSWORD="你的密码"                      # 与 B 服务器相同的密码
USE_TLS=false                            # 如果用 HTTPS，改为 true
```

### 4. 运行客户端

```bash
# 前台测试运行
./run-client.sh

# 看到以下信息表示成功：
# 🚀 WebSocket 隧道客户端启动
# 📍 本地监听: 127.0.0.1:1080
# 🌐 服务器: ws://2.2.2.2:8080/mm
# ✅ 等待连接...
```

### 5. 后台运行

```bash
# 使用 screen
screen -S tunnel-client
./run-client.sh
# Ctrl+A, D 退出

# 或使用 systemd
sudo tee /etc/systemd/system/ws-tunnel-client.service > /dev/null <<EOF
[Unit]
Description=WebSocket Tunnel Client
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/root/ws-tunnel-client-linux -local 127.0.0.1:1080 -server ws://2.2.2.2:8080/mm -password "你的密码"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ws-tunnel-client
sudo systemctl start ws-tunnel-client
```

---

## 🧪 测试验证

### 1. 测试 B 服务器

```bash
# 在 B 服务器上
curl http://localhost:8080/
# 应返回 nginx 欢迎页（伪装成功）

curl http://localhost:8080/test
# 应返回 nginx 欢迎页（非法路径被拦截）
```

### 2. 测试 A 服务器本地端口

```bash
# 在 A 服务器上
telnet 127.0.0.1 1080
# 应成功连接

# 或者
nc -zv 127.0.0.1 1080
```

### 3. 查看日志

```bash
# B 服务器
screen -r tunnel-server
# 或
journalctl -u ws-tunnel -f

# A 服务器
screen -r tunnel-client
# 或
journalctl -u ws-tunnel-client -f
```

---

## 📊 完整流量路径

```
应用程序
  ↓
A 服务器 127.0.0.1:1080 (ws-tunnel-client)
  ↓ WebSocket 加密 + 密码认证
B 服务器 2.2.2.2:8080/mm (ws-tunnel-server)
  ↓ 转发 WebSocket 握手
C 服务器 3.3.3.3:20001/mm (HAProxy)
  ↓ 路径验证 + 反探测
后端服务器
```

---

## 🔧 常用命令

### 查看进程

```bash
ps aux | grep ws-tunnel
```

### 查看端口

```bash
ss -tlnp | grep 8080
ss -tlnp | grep 1080
```

### 停止服务

```bash
# 使用 screen
screen -S tunnel-server -X quit
screen -S tunnel-client -X quit

# 使用 systemd
systemctl stop ws-tunnel
systemctl stop ws-tunnel-client
```

### 重启服务

```bash
systemctl restart ws-tunnel
systemctl restart ws-tunnel-client
```

---

## 🆘 故障排查

### B 服务器无法连接 C

```bash
# 测试连通性
ping 3.3.3.3
telnet 3.3.3.3 20001

# 检查 C 服务器防火墙
# 在 C 服务器上：
ufw allow from 2.2.2.2 to any port 20001
```

### A 服务器无法连接 B

```bash
# 测试连通性
ping 2.2.2.2
telnet 2.2.2.2 8080

# 检查 B 服务器防火墙
# 在 B 服务器上：
ufw allow 8080/tcp
```

### 密码错误

确保 A 和 B 使用完全相同的密码（区分大小写）

---

## 📝 文件清单

```
.
├── bin/
│   ├── ws-tunnel-server-linux       # B 服务器程序
│   └── ws-tunnel-client-linux       # A 服务器程序
├── build.sh                         # 编译脚本
├── run-server.sh                    # B 服务器启动脚本
└── run-client.sh                    # A 服务器启动脚本
```

---

## ✅ 部署完成

现在你的隧道已经打通：

```
A (1.1.1.1):1080 → B (2.2.2.2):8080 → C (3.3.3.3):20001 HAProxy
```

所有通过 A 服务器 `127.0.0.1:1080` 的流量，都会通过加密 WebSocket 隧道，经过 B 服务器中转，最终到达 C 服务器的 HAProxy！

🎉 祝使用愉快！
