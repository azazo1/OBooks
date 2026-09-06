package httpapi

import (
	"net"
	"net/http"
	"sync"
	"time"
)

const (
	limiterWindow    = time.Minute
	limiterMaxKeys   = 10000
	loginLimit       = 10
	loginConcurrency = 2
	errorLimit       = 20
)

type attemptLimiter struct {
	mu       sync.Mutex
	attempts map[string][]time.Time
	now      func() time.Time
	window   time.Duration
	perKey   int
	maxKeys  int
}

func newAttemptLimiter(window time.Duration, perKey, maxKeys int) *attemptLimiter {
	return &attemptLimiter{attempts: map[string][]time.Time{}, window: window, perKey: perKey, maxKeys: maxKeys}
}

func (l *attemptLimiter) timeNow() time.Time {
	if l.now != nil {
		return l.now()
	}
	return time.Now()
}

func (l *attemptLimiter) liveLocked(key string, now time.Time) []time.Time {
	entries := l.attempts[key]
	i := 0
	for i < len(entries) && now.Sub(entries[i]) >= l.window {
		i++
	}
	if i == len(entries) {
		delete(l.attempts, key)
		return nil
	}
	if i > 0 {
		entries = entries[i:]
		l.attempts[key] = entries
	}
	return entries
}

func (l *attemptLimiter) gcLocked(now time.Time) {
	for key := range l.attempts {
		l.liveLocked(key, now)
	}
}

func (l *attemptLimiter) overLocked(key string, now time.Time) bool {
	if len(l.liveLocked(key, now)) >= l.perKey {
		return true
	}
	if _, known := l.attempts[key]; known || len(l.attempts) < l.maxKeys {
		return false
	}
	l.gcLocked(now)
	_, known := l.attempts[key]
	return !known && len(l.attempts) >= l.maxKeys
}

func (l *attemptLimiter) blocked(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.overLocked(key, l.timeNow())
}

func (l *attemptLimiter) charge(key string) (recorded, reached bool) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.timeNow()
	if l.overLocked(key, now) {
		return false, true
	}
	l.attempts[key] = append(l.attempts[key], now)
	return true, len(l.attempts[key]) >= l.perKey
}

func clientIP(r *http.Request) string {
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return ip
}

func isClientError(status int) bool {
	return status >= 400 && status < 500 && status != http.StatusTooManyRequests
}
