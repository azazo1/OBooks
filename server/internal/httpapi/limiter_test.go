package httpapi

import (
	"testing"
	"time"
)

func TestAttemptLimiterWindowAndCapacity(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	l := newAttemptLimiter(time.Minute, 3, 2)
	l.now = func() time.Time { return now }
	for i := 0; i < 3; i++ {
		recorded, reached := l.charge("a")
		if !recorded {
			t.Fatal("未记入窗口内请求")
		}
		if reached != (i == 2) {
			t.Fatalf("reached=%v i=%d", reached, i)
		}
	}
	if recorded, _ := l.charge("a"); recorded {
		t.Fatal("未拦截超限来源")
	}
	if !l.blocked("a") {
		t.Fatal("超限后未阻止")
	}
	if recorded, _ := l.charge("b"); !recorded {
		t.Fatal("未记入另一来源")
	}
	if recorded, _ := l.charge("c"); recorded {
		t.Fatal("未限制来源数量")
	}
	now = now.Add(time.Minute)
	if l.blocked("a") {
		t.Fatal("窗口结束后仍限流")
	}
	if recorded, _ := l.charge("c"); !recorded {
		t.Fatal("窗口结束后仍拒绝新来源")
	}
}
