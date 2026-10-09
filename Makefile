# WebSocket 隧道编译脚本

.PHONY: all server client clean install

all: server client

# 编译服务端
server:
	@echo "🔨 编译服务端..."
	go build -o ws-tunnel-server ws-tunnel-server.go

# 编译客户端
client:
	@echo "🔨 编译客户端..."
	go build -o ws-tunnel-client ws-tunnel-client.go

# 安装依赖
install:
	@echo "📦 安装依赖..."
	go mod download

# 编译 Linux 版本（交叉编译）
linux:
	@echo "🐧 编译 Linux 版本..."
	GOOS=linux GOARCH=amd64 go build -o ws-tunnel-server-linux ws-tunnel-server.go
	GOOS=linux GOARCH=amd64 go build -o ws-tunnel-client-linux ws-tunnel-client.go

# 编译 Windows 版本
windows:
	@echo "🪟 编译 Windows 版本..."
	GOOS=windows GOARCH=amd64 go build -o ws-tunnel-server.exe ws-tunnel-server.go
	GOOS=windows GOARCH=amd64 go build -o ws-tunnel-client.exe ws-tunnel-client.go

# 清理
clean:
	@echo "🧹 清理编译文件..."
	rm -f ws-tunnel-server ws-tunnel-client
	rm -f ws-tunnel-server-linux ws-tunnel-client-linux
	rm -f ws-tunnel-server.exe ws-tunnel-client.exe

# 测试运行服务端
run-server:
	./ws-tunnel-server -listen :8080 -path /mm -target 3.3.3.3:20001 -password your_secret_password

# 测试运行客户端
run-client:
	./ws-tunnel-client -local 127.0.0.1:1080 -server ws://2.2.2.2:8080/mm -password your_secret_password
