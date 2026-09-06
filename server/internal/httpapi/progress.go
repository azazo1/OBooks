package httpapi

import (
	"io"
	"log/slog"
	"time"
)

type uploadProgress struct {
	reader io.Reader
	logger *slog.Logger
	bytes int64
	lastReport time.Time
}

func (p *uploadProgress) Read(buffer []byte) (int, error) {
	n, err := p.reader.Read(buffer)
	p.bytes += int64(n)
	if time.Since(p.lastReport) >= 5*time.Second {
		p.logger.Info("文件上传中", "bytes", p.bytes)
		p.lastReport = time.Now()
	}
	return n, err
}
