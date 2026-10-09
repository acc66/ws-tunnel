# 推送到 GitHub 说明

## 当前状态

✅ 代码已提交到本地 Git 仓库
✅ 所有文件已准备就绪
✅ 支持全平台编译（Linux, Windows, macOS, ARM）

## 快速推送步骤

### 1. 在 GitHub 创建新仓库

访问：https://github.com/new

- Repository name: `ws-tunnel`
- Description: `WebSocket Tunnel - Simple and efficient tunnel tool`
- Public (推荐) 或 Private
- ❌ 不要勾选 "Initialize this repository with a README"
- 点击 "Create repository"

### 2. 推送代码

在当前目录执行以下命令（替换你的用户名）：

```bash
# 设置远程仓库（替换 YOUR_USERNAME）
git remote add origin https://github.com/YOUR_USERNAME/ws-tunnel.git

# 重命名分支为 main
git branch -M main

# 推送
git push -u origin main
```

### 3. 创建第一个 Release（触发自动编译）

```bash
# 创建标签
git tag v1.0.0

# 推送标签
git push origin v1.0.0
```

或者在 GitHub 网页上：
1. 进入你的仓库
2. 点击右侧 "Releases" → "Create a new release"
3. Tag version: `v1.0.0`
4. Release title: `v1.0.0 - First Release`
5. Description: 复制下面的内容

```markdown
## WebSocket Tunnel v1.0.0

首次发布！支持全平台的 WebSocket 隧道工具。

### ✨ 功能特性

- 🔒 路径保护 - 只有 `/mm` 可访问
- 🔑 密码认证 - Bearer Token 验证
- 🎭 防探测伪装 - 伪装成 nginx 服务器
- 🚀 高性能 - Go 协程并发处理
- 🌐 全平台支持 - Linux, Windows, macOS (x64/ARM64)

### 📥 下载

请从下方 Assets 下载对应平台的版本。

### 🚀 快速开始

**服务端 (B 服务器):**
```bash
./ws-tunnel-server-linux-amd64 \
  -listen :8080 \
  -path /mm \
  -haproxy-ip 3.3.3.3 \
  -haproxy-port 20001 \
  -password "your_password"
```

**客户端 (A 服务器):**
```bash
./ws-tunnel-client-linux-amd64 \
  -local 127.0.0.1:1080 \
  -server ws://2.2.2.2:8080/mm \
  -password "your_password"
```

查看 [QUICK-START.md](QUICK-START.md) 获取详细使用说明。
```

4. 点击 "Publish release"

### 4. GitHub Actions 自动编译

发布 Release 后，GitHub Actions 会自动：
- 编译所有平台的版本（Linux, Windows, macOS, ARM64）
- 生成 SHA256 校验和
- 自动上传到 Release 页面

大约 3-5 分钟后，你就能在 Release 页面看到所有编译好的文件！

## 文件清单

推送到 GitHub 的文件：

```
ws-tunnel/
├── .github/workflows/release.yml   # 自动编译配置
├── .gitignore
├── LICENSE
├── README.md                       # 主文档
├── QUICK-START.md                  # 快速开始
├── README-COMPLETE.md              # 完整文档
├── Dockerfile.server               # Docker 镜像 - 服务端
├── Dockerfile.client               # Docker 镜像 - 客户端
├── docker-compose.yml              # Docker Compose
├── go.mod                          # Go 依赖
├── ws-tunnel-to-haproxy.go         # 服务端源码
├── ws-tunnel-client.go             # 客户端源码
├── build-all-platforms.sh          # 本地编译脚本
├── run-server.sh                   # 服务端启动脚本
└── run-client.sh                   # 客户端启动脚本
```

## 如果推送失败

如果遇到认证问题，需要创建 Personal Access Token：

1. 访问：https://github.com/settings/tokens
2. 点击 "Generate new token (classic)"
3. 勾选权限：
   - ✅ repo (full control)
   - ✅ workflow
4. 生成 token 并复制
5. 推送时使用：

```bash
git remote set-url origin https://YOUR_TOKEN@github.com/YOUR_USERNAME/ws-tunnel.git
git push -u origin main
```

## ���证推送成功

访问：https://github.com/YOUR_USERNAME/ws-tunnel

应该能看到：
- ✅ 所有源代码文件
- ✅ README.md 显示项目介绍
- ✅ .github/workflows/release.yml 配置文件

创建 Release 后，访问：
https://github.com/YOUR_USERNAME/ws-tunnel/releases

应该能看到：
- ✅ v1.0.0 Release
- ✅ 14 个编译好的可执行文件
- ✅ SHA256SUMS 校验文件
- ✅ 配置和文档文件

## 后续更新

如果需要更新代码：

```bash
# 修改代码后
git add .
git commit -m "Update: 描述你的修改"
git push

# 发布新版本
git tag v1.0.1
git push origin v1.0.1
```

---

## 需要我的帮助？

告诉我你的 GitHub 用户名，我可以直接帮你执行推送命令！
