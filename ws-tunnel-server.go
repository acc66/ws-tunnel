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
	targetAddr = flag.String("target", "3.3.3.3:20001", "转发目标地址（C 服务器）")
	password   = flag.String("password", "your_secret_password", "连接密码")
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  65536,
	WriteBufferSize: 65536,
	CheckOrigin: func(r *http.Request) bool {
		return true // 生产环境应该验证 Origin
	},
}

func main() {
	flag.Parse()

	http.HandleFunc(*wsPath, handleWebSocket)

	// 其他路径返回伪装页面（防探测）
	http.HandleFunc("/", handleFakePage)

	log.Printf("🚀 WebSocket 隧道服务器启动")
	log.Printf("📍 监听地址: %s", *listenAddr)
	log.Printf("🔑 WebSocket 路径: %s", *wsPath)
	log.Printf("🎯 转发目标: %s", *targetAddr)
	log.Printf("⚠️  其他路径将返回伪装页面")

	if err := http.ListenAndServe(*listenAddr, nil); err != nil {
		log.Fatal("启动失败:", err)
	}
}

// WebSocket 隧道处理
func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	// 验证密码（通过 HTTP Header）
	authHeader := r.Header.Get("Authorization")
	if authHeader != "Bearer "+*password {
		log.Printf("❌ 未授权访问: %s", r.RemoteAddr)
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// 升级为 WebSocket
	wsConn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("❌ WebSocket 升级失败: %v", err)
		return
	}
	defer wsConn.Close()

	log.Printf("✅ 新连接: %s", r.RemoteAddr)

	// 连接到目标服务器（C 服务器）
	targetConn, err := net.DialTimeout("tcp", *targetAddr, 10*time.Second)
	if err != nil {
		log.Printf("❌ 连接目标失败 %s: %v", *targetAddr, err)
		wsConn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseInternalServerErr, "target unreachable"))
		return
	}
	defer targetConn.Close()

	log.Printf("🔗 已连接目标: %s", *targetAddr)

	// 双向转发
	var wg sync.WaitGroup
	wg.Add(2)

	// WebSocket → Target
	go func() {
		defer wg.Done()
		defer targetConn.Close()

		for {
			msgType, data, err := wsConn.ReadMessage()
			if err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
					log.Printf("⚠️  WebSocket 读取错误: %v", err)
				}
				return
			}

			if msgType != websocket.BinaryMessage {
				continue
			}

			if _, err := targetConn.Write(data); err != nil {
				log.Printf("⚠️  写入目标失败: %v", err)
				return
			}
		}
	}()

	// Target → WebSocket
	go func() {
		defer wg.Done()
		defer wsConn.Close()

		buf := make([]byte, 32768)
		for {
			n, err := targetConn.Read(buf)
			if err != nil {
				if err != io.EOF {
					log.Printf("⚠️  读取目标失败: %v", err)
				}
				return
			}

			if err := wsConn.WriteMessage(websocket.BinaryMessage, buf[:n]); err != nil {
				log.Printf("⚠️  WebSocket 写入错误: %v", err)
				return
			}
		}
	}()

	wg.Wait()
	log.Printf("🔌 连接关闭: %s", r.RemoteAddr)
}

// 伪装页面（防止探测）
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
