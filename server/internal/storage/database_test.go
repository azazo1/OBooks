package storage

import (
	"context"
	"testing"
)

func TestMigrationAndReopen(t *testing.T) {
	ctx := context.Background()
	directory := t.TempDir()
	db, err := Open(ctx, directory)
	if err != nil { t.Fatal(err) }
	var version int
	if err = db.QueryRow("PRAGMA user_version").Scan(&version); err != nil || version != 1 { t.Fatalf("版本无效: %d %v", version, err) }
	if _, err = db.Exec("INSERT INTO users(id,username,password_hash) VALUES('id','test','hash')"); err != nil { t.Fatal(err) }
	db.Close()
	db, err = Open(ctx, directory)
	if err != nil { t.Fatal(err) }
	var count int
	if err = db.QueryRow("SELECT COUNT(*) FROM users").Scan(&count); err != nil || count != 1 { t.Fatal("重新打开丢失数据") }
	if _, err = db.Exec("PRAGMA user_version = 2"); err != nil { t.Fatal(err) }
	db.Close()
	if newer, err := Open(ctx, directory); err == nil { newer.Close(); t.Fatal("未拒绝未来版本") }
}
