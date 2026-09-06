package migrations

import "embed"

// Files 保存按数据库版本执行的迁移脚本.
//go:embed *.sql
var Files embed.FS
