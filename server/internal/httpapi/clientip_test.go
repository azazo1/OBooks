package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func request(remoteAddr, forwarded string) *http.Request {
	r := httptest.NewRequest("POST", "/v1/auth/login", nil)
	r.RemoteAddr = remoteAddr
	if forwarded != "" { r.Header.Set("X-Forwarded-For", forwarded) }
	return r
}

func TestClientIPWithoutTrustedProxy(t *testing.T) {
	proxies, err := NewTrustedProxies(nil)
	if err != nil { t.Fatal(err) }
	// 直连流量必须忽略任何伪造的 X-Forwarded-For.
	for _, forwarded := range []string{"", "1.1.1.1", "9.9.9.9, 1.1.1.1", "garbage"} {
		if got := proxies.clientIP(request("203.0.113.7:443", forwarded)); got != "203.0.113.7" {
			t.Fatalf("forwarded=%q got=%s", forwarded, got)
		}
	}
	// nil 解析器等价于不受信任何代理.
	var missing *TrustedProxies
	if got := missing.clientIP(request("203.0.113.7:443", "1.1.1.1")); got != "203.0.113.7" {
		t.Fatalf("nil proxies got=%s", got)
	}
}

func TestClientIPBehindTrustedProxy(t *testing.T) {
	proxies, err := NewTrustedProxies(DefaultTrustedProxies)
	if err != nil { t.Fatal(err) }
	cases := []struct{ forwarded, expected string }{
		{"198.51.100.5", "198.51.100.5"},
		{"9.9.9.9, 198.51.100.5", "198.51.100.5"}, // 左侧是客户端伪造的, 只取最右非受信.
		{"198.51.100.5:8443", "198.51.100.5"},
		{"127.0.0.1", "127.0.0.1"}, // 链上全是受信代理, 回退到代理地址.
		{"not-an-ip", "127.0.0.1"},
		{"", "127.0.0.1"},
	}
	for _, item := range cases {
		if got := proxies.clientIP(request("127.0.0.1:9999", item.forwarded)); got != item.expected {
			t.Fatalf("forwarded=%q got=%s, expected=%s", item.forwarded, got, item.expected)
		}
	}
	if got := proxies.clientIP(request("[::1]:80", "")); got != "::1" {
		t.Fatalf("ipv6 loopback got=%s", got)
	}
}

func TestNewTrustedProxiesValidation(t *testing.T) {
	if _, err := NewTrustedProxies([]string{"10.0.0.0/8", "192.168.1.1", "fd00::/8"}); err != nil {
		t.Fatal(err)
	}
	if _, err := NewTrustedProxies([]string{"no-ip-here"}); err == nil {
		t.Fatal("expected error for invalid entry")
	}
}
