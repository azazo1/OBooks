package httpapi

import (
	"fmt"
	"net"
	"net/http"
	"strings"
)

// DefaultTrustedProxies 默认只信任本机回环, 覆盖 nginx 在同一台机器反代的部署.
var DefaultTrustedProxies = []string{"127.0.0.1/32", "::1/128"}

// TrustedProxies 判定请求是否来自受信反向代理, 为 nil 时视为不存在任何受信代理.
type TrustedProxies struct { networks []*net.IPNet }

func NewTrustedProxies(entries []string) (*TrustedProxies, error) {
	list := &TrustedProxies{}
	for _, entry := range entries {
		if ip := net.ParseIP(entry); ip != nil {
			if ip.To4() != nil { entry += "/32" } else { entry += "/128" }
		}
		_, network, err := net.ParseCIDR(entry)
		if err != nil { return nil, fmt.Errorf("受信代理无效: %s", entry) }
		list.networks = append(list.networks, network)
	}
	return list, nil
}

func (t *TrustedProxies) contains(ip net.IP) bool {
	if t == nil { return false }
	for _, network := range t.networks {
		if network.Contains(ip) { return true }
	}
	return false
}

// clientIP 返回限流使用的客户端地址: 请求直接来自受信代理时, 采用 X-Forwarded-For
// 中从右向左第一个不受信的地址, 左侧内容可能是客户端伪造的, 不能采用.
func (t *TrustedProxies) clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil { host = r.RemoteAddr }
	ip := net.ParseIP(host)
	if ip == nil || !t.contains(ip) { return host }
	parts := strings.Split(r.Header.Get("X-Forwarded-For"), ",")
	for i := len(parts) - 1; i >= 0; i-- {
		candidate := strings.TrimSpace(parts[i])
		if bare, _, err := net.SplitHostPort(candidate); err == nil { candidate = bare }
		parsed := net.ParseIP(candidate)
		if parsed == nil { return host }
		if !t.contains(parsed) { return parsed.String() }
	}
	return host
}
