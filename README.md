# WebSocket Tunnel - 简单高效的隧道工具

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Go Version](https://img.shields.io/badge/Go-1.19+-blue.svg)](https://golang.org)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Windows%20%7C%20macOS-lightgrey.svg)](https://github.com)

一个简单高效的 WebSocket 隧道工具，用于建立安全的网络隧道。支持路径保护、密码认证、防探测伪装。

## ✨ 特性

- 🔒 **路径保护** - 只有指定路径（`/mm`）可访问，其他路径返回伪装页面
- 🔑 **密码认证** - Bearer Token 方式，防止未授权访问
- 🎭 **防探测伪装** - 非法访问返回 nginx 欢迎页，伪装成普通 Web 服务器
- 🚀 **高性能** - Go 语言实现，协程并发处理，支持大量连接
- 🌐 **跨平台** - 支持 Linux、Windows、macOS（x64/ARM64）
- 📦 **开箱即用** - 单个二进制文件，无需安装依赖

## 🏗️ 架构

```
A 服务器 (客户端)      →      B 服务器 (隧道)      →      C 服务器 (HAProxy)
   1.1.1.1                      2.2.2.2                    3.3.3.3
     ↓                             ↓                          ↓
ws-tunnel-client          ws-tunnel-server              HAProxy (你的配置)
  监听 127.0.0.1:1080       监听 0.0.0.0:8080           监听 0.0.0.0:20001
     ↓                             ↓                          ↓
   WebSocket 加密 + 密码认证    转发 WebSocket 到 HAProxy    路径验证 + 后端转发
```

## 📥 下载

前往 [Releases](../../releases) 页面下载对应平台的预编译版本：

### 服务端（B 服务器使用）
- Linux x64: `ws-tunnel-server-linux-amd64`
- Linux ARM64: `ws-tunnel-server-linux-arm64`
- Windows x64: `ws-tunnel-server-windows-amd64.exe`
- macOS Intel: `ws-tunnel-server-darwin-amd64`
- macOS Apple Silicon: `ws-tunnel-server-darwin-arm64`

### 客户端（A 服务器使用）
- Linux x64: `ws-tunnel-client-linux-amd64`
- Linux ARM64: `ws-tunnel-client-linux-arm64`
- Windows x64: `ws-tunnel-client-windows-amd64.exe`
- macOS Intel: `ws-tunnel-client-darwin-amd64`
- macOS Apple Silicon: `ws-tunnel-client-darwin-arm64`

## 🚀 快速开始

### 1. B 服务器（中转节点）

```bash
# 下载
wget https://github.com/YOUR_USERNAME/ws-tunnel/releases/latest/download/ws-tunnel-server-linux-amd64
chmod +x ws-tunnel-server-linux-amd64

# 运行
./ws-tunnel-server-linux-amd64 \
  -listen :8080 \
  -path /mm \
  -haproxy-ip 3.3.3.3 \
  -haproxy-port 20001 \
  -password "your_strong_password"
```

### 2. A 服务器（客户端）

```bash
# 下载
wget https://github.com/YOUR_USERNAME/ws-tunnel/releases/latest/download/ws-tunnel-client-linux-amd64
chmod +x ws-tunnel-client-linux-amd64

# 运行
./ws-tunnel-client-linux-amd64 \
  -local 127.0.0.1:1080 \
  -server ws://2.2.2.2:8080/mm \
  -password "your_strong_password"
```

### 3. 测试

```bash
# A 服务器测试
telnet 127.0.0.1 1080
# 成功连接表示隧道已打通
```

## 📖 详细文档

- [快速入门指南](QUICK-START.md) - 3 步完成部署
- [完整使用文档](README-COMPLETE.md) - 详细配置、测试、故障排查

## 🔧 参数说明

### 服务端参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-listen` | `:8080` | 监听地址和端口 |
| `-path` | `/mm` | WebSocket 路径（只有此路径可访问） |
| `-haproxy-ip` | `3.3.3.3` | HAProxy 服务器 IP |
| `-haproxy-port` | `20001` | HAProxy 服务器端口 |
| `-password` | `your_secret_password` | 连接密码 |

### 客户端参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-local` | `127.0.0.1:1080` | 本地监听地址 |
| `-server` | `ws://2.2.2.2:8080/mm` | WebSocket 服务器地址 |
| `-password` | `your_secret_password` | 连接密码（与服务端相同） |
| `-tls` | `false` | 使用 WSS (TLS) |

## 🔒 使用 TLS/HTTPS（推荐）

### 方法 1：使用 Nginx 反向代理

在 B 服务器上配置 Nginx：

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location /mm {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Authorization $http_authorization;
    }
}
```

客户端连接：
```bash
./ws-tunnel-client-linux-amd64 \
  -local 127.0.0.1:1080 \
  -server wss://your-domain.com/mm \
  -password "your_password" \
  -tls
```

## 🐳 Docker 部署

### 服务端

```bash
docker run -d \
  --name ws-tunnel-server \
  --restart always \
  -p 8080:8080 \
  your-image \
  -listen :8080 \
  -path /mm \
  -haproxy-ip 3.3.3.3 \
  -haproxy-port 20001 \
  -password "your_password"
```

### 客户端

```bash
docker run -d \
  --name ws-tunnel-client \
  --restart always \
  -p 1080:1080 \
  your-image \
  -local 0.0.0.0:1080 \
  -server ws://2.2.2.2:8080/mm \
  -password "your_password"
```

## 🛠️ 从源码编译

```bash
# 克隆仓库
git clone https://github.com/YOUR_USERNAME/ws-tunnel.git
cd ws-tunnel

# 安装依赖
go mod download

# 编译当前平台
go build -o ws-tunnel-server ws-tunnel-to-haproxy.go
go build -o ws-tunnel-client ws-tunnel-client.go

# 编译所有平台
chmod +x build-all-platforms.sh
./build-all-platforms.sh
```

## 📊 性能优化

### 系统参数优化

```bash
# 增加文件描述符限制
ulimit -n 100000

# /etc/sysctl.conf
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65535

sysctl -p
```

## 🐛 故障排查

### 服务端无法连接 HAProxy

```bash
# 测试连通性
telnet 3.3.3.3 20001

# 检查防火墙
ufw allow from 2.2.2.2 to any port 20001
```

### 客户端连接失败

```bash
# 测试服务端
curl http://2.2.2.2:8080/

# 检查密码是否一致
# 查看日志排查问题
```

### 查看日志

```bash
# 使用 systemd
journalctl -u ws-tunnel-server -f
journalctl -u ws-tunnel-client -f

# 或直接运行查看输出
./ws-tunnel-server-linux-amd64 -listen :8080 ...
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

[MIT License](LICENSE)

## ⭐ Star History

如果这个项目对你有帮助，请给个 Star ⭐️

## 📞 联系方式

- Issue: [GitHub Issues](../../issues)
- Email: your-email@example.com

## 🙏 致谢

感谢所有贡献者和使用者！

---

**注意**：本工具仅供学习和合法用途，请遵守当地法律法规。
