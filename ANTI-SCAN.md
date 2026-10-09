# 🛡️ 防扫描隧道方案对比

## 方案 1：Nginx 反向代理 + 真实网站（推荐）⭐⭐⭐⭐⭐

**特点：**
- ✅ 80/443 端口看起来像正常企业网站
- ✅ 扫描器访问任何路径都返回真实网站内容
- ✅ 只有 `/mm` + 正确密码才能连接隧道
- ✅ 可以添加 SSL 证书（Let's Encrypt 免费）
- ✅ 日志分离：网站访问不记录，隧道访问单独记录

**部署：**
```bash
# B 服务器执行
chmod +x deploy-camouflage.sh
./deploy-camouflage.sh
```

**效果：**
- 扫描器看到：正常的企业网站
- 真实用户：通过 WebSocket 隧道连接

---

## 方案 2：CDN 套娃（Cloudflare）⭐⭐⭐⭐

**架构：**
```
客户端 → Cloudflare CDN → B 服务器(隧道) → HAProxy
```

**优点：**
- ✅ B 服务器真实 IP 隐藏
- ✅ Cloudflare 自带 DDoS 防护
- ✅ 免费 SSL 证书
- ✅ 全球 CDN 加速

**步骤：**
1. 注册域名（Namecheap $0.88/年）
2. 域名接入 Cloudflare
3. A 记录指向 B 服务器
4. 开启橙色云朵（代理模式）
5. 客户端连接域名而非 IP

**配置：**
```bash
# A 服务器客户端改为域名
./ws-tunnel-client-linux-amd64 \
  -local 0.0.0.0:1080 \
  -server ws://yourdomain.com/mm \
  -password "66880"
```

---

## 方案 3：端口敲门（Port Knocking）⭐⭐⭐

**原理：**
- 隧道端口默认关闭
- 客户端先访问特定端口序列（敲门）
- 防火墙才临时开放隧道端口

**实现：**
```bash
# B 服务器安装 knockd
apt install knockd

# 配置 /etc/knockd.conf
[openSSH]
    sequence    = 7000,8000,9000
    seq_timeout = 5
    command     = /sbin/iptables -A INPUT -s %IP% -p tcp --dport 8080 -j ACCEPT
    tcpflags    = syn

[closeSSH]
    sequence    = 9000,8000,7000
    seq_timeout = 5
    command     = /sbin/iptables -D INPUT -s %IP% -p tcp --dport 8080 -j ACCEPT
    tcpflags    = syn

# A 服务器敲门
knock 43.198.243.20 7000 8000 9000
./ws-tunnel-client-linux-amd64 -local 0.0.0.0:1080 -server ws://43.198.243.20:8080/mm -password "66880"
```

---

## 方案 4：时间窗口限制⭐⭐⭐

**原理：**
- 只在特定时间段开放隧道
- 或基于时间戳的动态密码

**实现：**
```bash
# 修改隧道代码，验证时间戳
# 密码格式: 固定密码 + 时间戳
# 例如: 66880_20261006_0130 （10分钟有效）
```

---

## 方案 5：IP 白名单⭐⭐⭐⭐

**实现：**
```bash
# B 服务器防火墙只允许 A 服务器 IP
ufw default deny incoming
ufw allow from 120.233.6.179 to any port 8080
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable

# 或在 Nginx 中限制
location /mm {
    allow 120.233.6.179;
    deny all;
    proxy_pass http://127.0.0.1:8080;
}
```

---

## 方案 6：多层跳板（最安全但复杂）⭐⭐⭐⭐⭐

**架构：**
```
A → CDN → B(伪装网站) → C(内网隧道) → D(HAProxy)
```

**优点：**
- B 服务器只运行 Nginx，看起来完全正常
- 真实隧道在内网 C 服务器
- 即使 B 被查也查不到隧道

---

## 🎯 推荐组合方案

**最优方案：Nginx 伪装 + Cloudflare CDN + IP 白名单**

```
客户端
  ↓
Cloudflare CDN (yourdomain.com)
  ↓ (隐藏真实IP)
Nginx 80/443 (真实企业网站)
  ↓ location /mm 限制来源IP
隧道服务器 (127.0.0.1:8080)
  ↓ 密码验证
HAProxy
```

**部署步骤：**

1. **部署伪装网站（立即执行）：**
```bash
chmod +x deploy-camouflage.sh
./deploy-camouflage.sh
```

2. **测试伪装效果：**
```bash
# 正常访问（返回企业网站）
curl http://43.198.243.20/

# 扫描常见路径（返回 404）
curl http://43.198.243.20/admin

# 访问隧道路径无密码（返回 401）
curl http://43.198.243.20/mm
```

3. **可选：接入 Cloudflare（推荐）**
- 注册域名
- DNS 指向 43.198.243.20
- 开启 Cloudflare 代理

---

## 📊 效果对比

| 方案 | 安全性 | 成本 | 复杂度 | 速度 |
|------|--------|------|--------|------|
| 原方案 | ⭐⭐ | 免费 | 简单 | 快 |
| Nginx伪装 | ⭐⭐⭐⭐ | 免费 | 简单 | 快 |
| +Cloudflare | ⭐⭐⭐⭐⭐ | $0.88/年 | 中等 | 中等 |
| +IP白名单 | ⭐⭐⭐⭐⭐ | 免费 | 简单 | 快 |
| 多层跳板 | ⭐⭐⭐⭐⭐ | 多台VPS | 复杂 | 慢 |

---

**先执行 `deploy-camouflage.sh` 脚本，立即提升安全性！** 🚀
