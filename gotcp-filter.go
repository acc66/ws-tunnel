package main

// A 服务器 TCP 中转 + 反探测过滤
// 客户端 → A(本程序) → B
// - 首个 HTTP 请求路径不是 /mm → 拉黑IP（写入 Redis，与 hp/export_scanners.sh 同结构）+ 返回蜜罐页
// - 路径是 /mm 但不是 WebSocket → 返回蜜罐页，不拉黑
// - 黑名单IP → 403
// - 合法请求 → 原样 TCP 转发到 B（含 Host 头，B 的 HAProxy 照常按域名分流）
// 黑名单定期从 Redis bl:rank 拉取，多节点共享

import (
	"bufio"
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

var (
	listenAddrs = flag.String("listen", ":20001", "监听地址，多个用逗号分隔，如 :20001,:58888")
	targetAddr  = flag.String("target", "", "B 服务器地址 ip:port（必填）")
	validPath   = flag.String("path", "/mm", "合法路径")
	envFile     = flag.String("env", "/etc/haproxy/blacklist.env", "Redis 配置文件（REDIS_HOST/REDIS_PORT/REDIS_PASS/NODE_ID）")
	redisHost   = flag.String("redis-host", "127.0.0.1", "Redis 地址（未指定时读取 env 文件）")
	redisPort   = flag.String("redis-port", "6379", "Redis 端口")
	redisPass   = flag.String("redis-pass", "", "Redis 密码")
	nodeID      = flag.String("node", "", "节点标识（默认主机名）")
	syncEvery   = flag.Duration("sync", 60*time.Second, "从 Redis 同步黑名单间隔")
	allowList   = flag.String("allow", "", "永不拉黑的IP，逗号分隔（自己的测试IP等）")
	banInvalid  = flag.Bool("ban-invalid", false, "非 HTTP 数据（无法解析的请求）也拉黑")
)

const (
	headerTimeout = 10 * time.Second
	maxHeaderSize = 16 * 1024
	redisTimeout  = 3 * time.Second

	// 与 hp/export_scanners.sh 保持一致
	banLua = `local ip=ARGV[1] local node=ARGV[2] local ts=ARGV[3] local key="bl:"..ip local count=redis.call("HINCRBY",key,"count",1) redis.call("HSET",key,"ip",ip,"node",node,"last",ts) if count==1 then redis.call("HSET",key,"first",ts) end redis.call("ZADD","bl:rank",count,ip) return count`

	honeypotHTML = `<!DOCTYPE html><html><head><title>Welcome to nginx!</title><style>body{width:35em;margin:0 auto;font-family:Tahoma,Verdana,Arial,sans-serif}</style></head><body><h1>Welcome to nginx!</h1><p>If you see this page, the nginx web server is successfully installed and working. Further configuration is required.</p><p>For online documentation and support please refer to <a href="http://nginx.org/">nginx.org</a>.</p><p><em>Thank you for using nginx.</em></p></body></html>`
	forbiddenHTML = `<html><body><h1>403 Forbidden</h1>
Request forbidden by administrative rules.
</body></html>
`
)

// ==================== 黑名单 ====================

type blacklist struct {
	mu      sync.RWMutex
	ips     map[string]struct{} // Redis 中的 + 本地新增的
	pending map[string]struct{} // 写 Redis 失败、待重试的
	allow   map[string]struct{}
}

func newBlacklist(allow string) *blacklist {
	b := &blacklist{
		ips:     map[string]struct{}{},
		pending: map[string]struct{}{},
		allow:   map[string]struct{}{},
	}
	for _, ip := range strings.Split(allow, ",") {
		if ip = strings.TrimSpace(ip); ip != "" {
			b.allow[normalizeIP(ip)] = struct{}{}
		}
	}
	return b
}

func (b *blacklist) has(ip string) bool {
	b.mu.RLock()
	defer b.mu.RUnlock()
	_, ok := b.ips[ip]
	return ok
}

// add 返回 true 表示是新拉黑的IP
func (b *blacklist) add(ip string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	if _, ok := b.allow[ip]; ok {
		return false
	}
	if _, ok := b.ips[ip]; ok {
		return false
	}
	b.ips[ip] = struct{}{}
	return true
}

func (b *blacklist) markPending(ip string, failed bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if failed {
		b.pending[ip] = struct{}{}
	} else {
		delete(b.pending, ip)
	}
}

// replace 用 Redis 数据整体替换（Redis 中删除的IP即视为解封），保留待重试的
func (b *blacklist) replace(redisIPs []string) int {
	b.mu.Lock()
	defer b.mu.Unlock()
	next := make(map[string]struct{}, len(redisIPs)+len(b.pending))
	for _, ip := range redisIPs {
		ip = normalizeIP(ip)
		if _, ok := b.allow[ip]; ok {
			continue
		}
		next[ip] = struct{}{}
	}
	for ip := range b.pending {
		next[ip] = struct{}{}
	}
	b.ips = next
	return len(next)
}

func (b *blacklist) pendingList() []string {
	b.mu.RLock()
	defer b.mu.RUnlock()
	out := make([]string, 0, len(b.pending))
	for ip := range b.pending {
		out = append(out, ip)
	}
	return out
}

func normalizeIP(s string) string {
	ip := net.ParseIP(strings.TrimSpace(s))
	if ip == nil {
		return strings.TrimSpace(s)
	}
	if v4 := ip.To4(); v4 != nil {
		return v4.String() // ::ffff:1.2.3.4 → 1.2.3.4，与 HAProxy 导出的格式一致
	}
	return ip.String()
}

// ==================== 极简 Redis 客户端（RESP，无第三方依赖） ====================

func redisDo(args ...string) (interface{}, error) {
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(*redisHost, *redisPort), redisTimeout)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(redisTimeout * 3))
	r := bufio.NewReader(conn)

	if *redisPass != "" {
		if _, err := redisCmd(conn, r, "AUTH", *redisPass); err != nil {
			return nil, fmt.Errorf("AUTH: %w", err)
		}
	}
	return redisCmd(conn, r, args...)
}

func redisCmd(w io.Writer, r *bufio.Reader, args ...string) (interface{}, error) {
	var buf bytes.Buffer
	fmt.Fprintf(&buf, "*%d\r\n", len(args))
	for _, a := range args {
		fmt.Fprintf(&buf, "$%d\r\n%s\r\n", len(a), a)
	}
	if _, err := w.Write(buf.Bytes()); err != nil {
		return nil, err
	}
	return readRESP(r)
}

func readRESP(r *bufio.Reader) (interface{}, error) {
	line, err := r.ReadString('\n')
	if err != nil {
		return nil, err
	}
	line = strings.TrimRight(line, "\r\n")
	if line == "" {
		return nil, errors.New("redis: 空响应")
	}
	switch line[0] {
	case '+':
		return line[1:], nil
	case '-':
		return nil, errors.New("redis: " + line[1:])
	case ':':
		return strconv.ParseInt(line[1:], 10, 64)
	case '$':
		n, err := strconv.Atoi(line[1:])
		if err != nil || n < 0 {
			return nil, err
		}
		data := make([]byte, n+2)
		if _, err := io.ReadFull(r, data); err != nil {
			return nil, err
		}
		return string(data[:n]), nil
	case '*':
		n, err := strconv.Atoi(line[1:])
		if err != nil || n < 0 {
			return nil, err
		}
		arr := make([]interface{}, 0, n)
		for i := 0; i < n; i++ {
			v, err := readRESP(r)
			if err != nil {
				return nil, err
			}
			arr = append(arr, v)
		}
		return arr, nil
	}
	return nil, fmt.Errorf("redis: 未知响应 %q", line)
}

func redisBan(ip string) error {
	_, err := redisDo("EVAL", banLua, "0", ip, *nodeID, strconv.FormatInt(time.Now().Unix(), 10))
	return err
}

func redisFetchAll() ([]string, error) {
	v, err := redisDo("ZRANGE", "bl:rank", "0", "-1")
	if err != nil {
		return nil, err
	}
	arr, ok := v.([]interface{})
	if !ok {
		return nil, errors.New("redis: ZRANGE 返回类型错误")
	}
	out := make([]string, 0, len(arr))
	for _, x := range arr {
		if s, ok := x.(string); ok && s != "" {
			out = append(out, s)
		}
	}
	return out, nil
}

func syncLoop(bl *blacklist) {
	for {
		// 先补写之前失败的
		for _, ip := range bl.pendingList() {
			if err := redisBan(ip); err == nil {
				bl.markPending(ip, false)
			}
		}
		if ips, err := redisFetchAll(); err != nil {
			log.Printf("[WARN] Redis 同步失败: %v（继续使用本地黑名单）", err)
		} else {
			n := bl.replace(ips)
			log.Printf("Redis 同步完成，黑名单共 %d 个IP", n)
		}
		time.Sleep(*syncEvery)
	}
}

// ==================== 连接处理 ====================

func writeHTTP(c net.Conn, status, body string) {
	fmt.Fprintf(c, "HTTP/1.1 %s\r\nServer: nginx\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
		status, len(body), body)
}

// readHeader 读取首个 HTTP 请求头（到 \r\n\r\n），返回已读字节（转发给 B 时原样回放）
func readHeader(r *bufio.Reader) ([]byte, error) {
	var buf bytes.Buffer
	for {
		line, err := r.ReadSlice('\n')
		buf.Write(line)
		if err != nil && err != bufio.ErrBufferFull {
			return buf.Bytes(), err
		}
		if buf.Len() > maxHeaderSize {
			return buf.Bytes(), errors.New("请求头过大")
		}
		if err == nil && (len(line) == 2 && line[0] == '\r' || len(line) == 1) {
			return buf.Bytes(), nil
		}
	}
}

// parseRequest 解析请求行和 Upgrade 头
func parseRequest(head []byte) (method, path string, isWS bool, ok bool) {
	lines := strings.Split(string(head), "\r\n")
	parts := strings.Fields(lines[0])
	if len(parts) != 3 || !strings.HasPrefix(parts[2], "HTTP/") {
		return "", "", false, false
	}
	method = parts[0]
	path = parts[1]
	if u, err := url.ParseRequestURI(path); err == nil {
		path = u.Path // 去掉 ?query，与 HAProxy 的 path 匹配行为一致
	}
	for _, l := range lines[1:] {
		k, v, found := strings.Cut(l, ":")
		if found && strings.EqualFold(strings.TrimSpace(k), "Upgrade") &&
			strings.EqualFold(strings.TrimSpace(v), "websocket") {
			isWS = true
		}
	}
	return method, path, isWS, true
}

func ban(bl *blacklist, ip, reason string) {
	if !bl.add(ip) {
		return
	}
	log.Printf("🚫 拉黑 %s（%s）", ip, reason)
	go func() {
		if err := redisBan(ip); err != nil {
			log.Printf("[WARN] 写入 Redis 失败 %s: %v（稍后重试）", ip, err)
			bl.markPending(ip, true)
		}
	}()
}

func handle(c net.Conn, bl *blacklist) {
	defer c.Close()
	host, _, _ := net.SplitHostPort(c.RemoteAddr().String())
	ip := normalizeIP(host)

	if bl.has(ip) {
		c.SetDeadline(time.Now().Add(headerTimeout))
		writeHTTP(c, "403 Forbidden", forbiddenHTML)
		return
	}

	c.SetReadDeadline(time.Now().Add(headerTimeout))
	r := bufio.NewReaderSize(c, 4096)
	head, err := readHeader(r)
	if err != nil {
		// 超时/断开/非HTTP：不转发
		if *banInvalid && len(head) > 0 {
			ban(bl, ip, "非HTTP数据")
		}
		return
	}
	c.SetReadDeadline(time.Time{})

	method, path, isWS, ok := parseRequest(head)
	if !ok {
		if *banInvalid {
			ban(bl, ip, "非法请求行")
		}
		return
	}
	if path != *validPath {
		ban(bl, ip, fmt.Sprintf("%s %s", method, path))
		writeHTTP(c, "200 OK", honeypotHTML)
		return
	}
	if !isWS {
		// 路径正确但不是 WS：只给蜜罐，不拉黑（客户端可能先发普通探测）
		writeHTTP(c, "200 OK", honeypotHTML)
		return
	}

	up, err := net.DialTimeout("tcp", *targetAddr, 10*time.Second)
	if err != nil {
		log.Printf("❌ 连接 B 失败 %s: %v", *targetAddr, err)
		return
	}
	defer up.Close()
	if tc, ok := up.(*net.TCPConn); ok {
		tc.SetKeepAlive(true)
		tc.SetKeepAlivePeriod(30 * time.Second)
	}

	// 回放已读的请求头 + 缓冲区里剩余的数据
	if _, err := up.Write(head); err != nil {
		return
	}
	if n := r.Buffered(); n > 0 {
		rest, _ := r.Peek(n)
		if _, err := up.Write(rest); err != nil {
			return
		}
	}

	done := make(chan struct{}, 2)
	go func() {
		io.Copy(up, c)
		if tc, ok := up.(*net.TCPConn); ok {
			tc.CloseWrite()
		}
		done <- struct{}{}
	}()
	go func() {
		io.Copy(c, up)
		if tc, ok := c.(*net.TCPConn); ok {
			tc.CloseWrite()
		}
		done <- struct{}{}
	}()
	<-done
	// 一端结束后给另一端留 1 小时空闲上限，避免半开连接泄漏
	c.SetDeadline(time.Now().Add(time.Hour))
	up.SetDeadline(time.Now().Add(time.Hour))
	<-done
}

// loadEnv 读取 blacklist.env（KEY="VALUE" 格式），命令行显式参数优先
func loadEnv(path string, set map[string]bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		v = strings.Trim(strings.TrimSpace(v), `"'`)
		switch strings.TrimSpace(k) {
		case "REDIS_HOST":
			if !set["redis-host"] {
				*redisHost = v
			}
		case "REDIS_PORT":
			if !set["redis-port"] {
				*redisPort = v
			}
		case "REDIS_PASS":
			if !set["redis-pass"] {
				*redisPass = v
			}
		case "NODE_ID":
			if !set["node"] {
				*nodeID = v
			}
		}
	}
	log.Printf("已加载配置 %s", path)
}

func main() {
	flag.Parse()
	if *targetAddr == "" {
		log.Fatal("必须指定 -target B服务器ip:port")
	}
	set := map[string]bool{}
	flag.Visit(func(f *flag.Flag) { set[f.Name] = true })
	loadEnv(*envFile, set)
	if *nodeID == "" {
		*nodeID, _ = os.Hostname()
	}

	bl := newBlacklist(*allowList)
	go syncLoop(bl)

	addrs := strings.Split(*listenAddrs, ",")
	for _, a := range addrs {
		a = strings.TrimSpace(a)
		ln, err := net.Listen("tcp", a)
		if err != nil {
			log.Fatalf("监听 %s 失败: %v", a, err)
		}
		log.Printf("🚀 监听 %s → %s（合法路径 %s，节点 %s）", a, *targetAddr, *validPath, *nodeID)
		go func(ln net.Listener) {
			for {
				c, err := ln.Accept()
				if err != nil {
					log.Printf("Accept 错误: %v", err)
					time.Sleep(100 * time.Millisecond)
					continue
				}
				go handle(c, bl)
			}
		}(ln)
	}
	select {}
}
