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
	listenAddr = flag.String("listen", ":8080", "WebSocket 监听地址")
	wsPath     = flag.String("path", "/mm", "WebSocket 路径")
	targetAddr = flag.String("target", "xjpk1.help600.com:2086", "目标服务器地址")
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

	http.HandleFunc(*wsPath, handleWebSocketTunnel)
	http.HandleFunc("/", handleFakePage)

	log.Printf("🚀 WebSocket TCP 隧道服务器启动")
	log.Printf("📍 监听地址: %s", *listenAddr)
	log.Printf("🔑 WebSocket 路径: %s", *wsPath)
	log.Printf("🎯 目标地址: %s", *targetAddr)

	if err := http.ListenAndServe(*listenAddr, nil); err != nil {
		log.Fatal("启动失败:", err)
	}
}

func handleWebSocketTunnel(w http.ResponseWriter, r *http.Request) {
	// 验证密码
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

	log.Printf("✅ 新连接: %s → %s", r.RemoteAddr, *targetAddr)

	// 直接 TCP 连接到目标（不做 WebSocket 握手）
	tcpConn, err := net.DialTimeout("tcp", *targetAddr, 10*time.Second)
	if err != nil {
		log.Printf("❌ 连接目标失败 %s: %v", *targetAddr, err)
		return
	}
	defer tcpConn.Close()

	log.Printf("🔗 已连接目标: %s", *targetAddr)

	// 双向转发（WebSocket ↔ TCP）
	var wg sync.WaitGroup
	wg.Add(2)

	// WebSocket → TCP
	go func() {
		defer wg.Done()
		defer tcpConn.Close()

		for {
			msgType, data, err := wsConn.ReadMessage()
			if err != nil {
				return
			}

			if msgType == websocket.BinaryMessage {
				if _, err := tcpConn.Write(data); err != nil {
					return
				}
			}
		}
	}()

	// TCP → WebSocket
	go func() {
		defer wg.Done()
		defer wsConn.Close()

		buf := make([]byte, 32768)
		for {
			n, err := tcpConn.Read(buf)
			if err != nil {
				if err != io.EOF {
					log.Printf("⚠️  读取目标失败: %v", err)
				}
				return
			}

			if err := wsConn.WriteMessage(websocket.BinaryMessage, buf[:n]); err != nil {
				return
			}
		}
	}()

	wg.Wait()
	log.Printf("🔌 连接关闭: %s", r.RemoteAddr)
}

func handleFakePage(w http.ResponseWriter, r *http.Request) {
	log.Printf("🕵️  非法访问: %s %s", r.RemoteAddr, r.URL.Path)

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
</body>
</html>`

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Server", "nginx/1.18.0")
	fmt.Fprint(w, html)
}
