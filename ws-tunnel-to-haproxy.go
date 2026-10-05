package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var (
	// 命令行参数
	listenAddr = flag.String("listen", ":8080", "WebSocket 监听地址")
	wsPath     = flag.String("path", "/mm", "WebSocket 路径（只有此路径可访问）")
	haproxyIP  = flag.String("haproxy-ip", "3.3.3.3", "C 服务器 HAProxy IP")
	haproxyPort = flag.String("haproxy-port", "20001", "C 服务器 HAProxy 端口")
	password   = flag.String("password", "your_secret_password", "连接密码")
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  65536,
	WriteBufferSize: 65536,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func main() {
	flag.Parse()

	targetAddr := fmt.Sprintf("%s:%s", *haproxyIP, *haproxyPort)

	http.HandleFunc(*wsPath, func(w http.ResponseWriter, r *http.Request) {
		handleWebSocketTunnel(w, r, targetAddr)
	})

	// 其他路径返回伪装页面
	http.HandleFunc("/", handleFakePage)

	log.Printf("🚀 WebSocket → HAProxy 隧道服务器启动")
	log.Printf("📍 监听地址: %s", *listenAddr)
	log.Printf("🔑 WebSocket 路径: %s", *wsPath)
	log.Printf("🎯 HAProxy 地址: %s", targetAddr)
	log.Printf("⚠️  其他路径将返回伪装页面")

	if err := http.ListenAndServe(*listenAddr, nil); err != nil {
		log.Fatal("启动失败:", err)
	}
}

// WebSocket 隧道处理 - 转发到 HAProxy
func handleWebSocketTunnel(w http.ResponseWriter, r *http.Request, haproxyAddr string) {
	// 验证密码
	authHeader := r.Header.Get("Authorization")
	if authHeader != "Bearer "+*password {
		log.Printf("❌ 未授权访问: %s %s", r.RemoteAddr, r.URL.Path)
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// 升级为 WebSocket
	clientWS, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("❌ WebSocket 升级失败: %v", err)
		return
	}
	defer clientWS.Close()

	log.Printf("✅ 新连接: %s → HAProxy %s", r.RemoteAddr, haproxyAddr)

	// 连接到 C 服务器的 HAProxy
	haproxyConn, err := net.DialTimeout("tcp", haproxyAddr, 10*time.Second)
	if err != nil {
		log.Printf("❌ 连接 HAProxy 失败 %s: %v", haproxyAddr, err)
		clientWS.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseInternalServerErr, "haproxy unreachable"))
		return
	}
	defer haproxyConn.Close()

	log.Printf("🔗 已连接到 HAProxy: %s", haproxyAddr)

	// 构造 HTTP Upgrade 请求发送给 HAProxy
	// 使用目标服务器的地址作为 Host
	targetHost := *haproxyIP
	if *haproxyPort != "80" && *haproxyPort != "443" {
		targetHost = fmt.Sprintf("%s:%s", *haproxyIP, *haproxyPort)
	}

	upgradeReq := fmt.Sprintf(
		"GET %s HTTP/1.1\r\n"+
			"Host: %s\r\n"+
			"Upgrade: websocket\r\n"+
			"Connection: Upgrade\r\n"+
			"Sec-WebSocket-Version: 13\r\n"+
			"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"+
			"\r\n",
		*wsPath, targetHost)

	if _, err := haproxyConn.Write([]byte(upgradeReq)); err != nil {
		log.Printf("❌ 发送 WebSocket 握手失败: %v", err)
		return
	}

	// 读取 HAProxy 的握手响应
	buf := make([]byte, 4096)
	n, err := haproxyConn.Read(buf)
	if err != nil {
		log.Printf("❌ 读取 HAProxy 握手响应失败: %v", err)
		return
	}

	response := string(buf[:n])
	if !contains(response, "101 Switching Protocols") && !contains(response, "HTTP/1.1 101") {
		log.Printf("❌ HAProxy WebSocket 握手失败: %s", response[:min(200, len(response))])
		return
	}

	log.Printf("✅ HAProxy WebSocket 握手成功")

	// 双向转发
	var wg sync.WaitGroup
	wg.Add(2)

	// 客户端 WebSocket → HAProxy
	go func() {
		defer wg.Done()
		defer haproxyConn.Close()

		for {
			msgType, data, err := clientWS.ReadMessage()
			if err != nil {
				if !websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
					log.Printf("⚠️  客户端断开: %v", err)
				}
				return
			}

			if msgType == websocket.BinaryMessage || msgType == websocket.TextMessage {
				if _, err := haproxyConn.Write(data); err != nil {
					log.Printf("⚠️  写入 HAProxy 失败: %v", err)
					return
				}
			}
		}
	}()

	// HAProxy → 客户端 WebSocket
	go func() {
		defer wg.Done()
		defer clientWS.Close()

		buf := make([]byte, 32768)
		for {
			n, err := haproxyConn.Read(buf)
			if err != nil {
				if err != io.EOF {
					log.Printf("⚠️  读取 HAProxy 失败: %v", err)
				}
				return
			}

			if err := clientWS.WriteMessage(websocket.BinaryMessage, buf[:n]); err != nil {
				log.Printf("⚠️  写入客户端失败: %v", err)
				return
			}
		}
	}()

	wg.Wait()
	log.Printf("🔌 连接关闭: %s", r.RemoteAddr)
}

// 伪装页面
func handleFakePage(w http.ResponseWriter, r *http.Request) {
	log.Printf("🕵️  非法访问路径 %s: %s", r.URL.Path, r.RemoteAddr)

	html := `<!DOCTYPE html>
<html>
<head>
    <title>Welcome to nginx!</title>
    <style>
        body { width: 35em; margin: 0 auto; font-family: Tahoma, Verdana, Arial, sans-serif; }
    </style>
</head>
<body>
    <h1>Welcome to nginx!</h1>
    <p>If you see this page, the nginx web server is successfully installed and working.</p>
    <p>For online documentation and support please refer to <a href="http://nginx.org/">nginx.org</a>.</p>
    <p><em>Thank you for using nginx.</em></p>
</body>
</html>`

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Server", "nginx/1.18.0")
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, html)
}

// 辅助函数
func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > len(substr) &&
		(s[:len(substr)] == substr || s[len(s)-len(substr):] == substr ||
		 len(s) > len(substr) && s[1:len(substr)+1] == substr))
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
