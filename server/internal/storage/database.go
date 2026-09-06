package storage

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"

	"obooks/server/migrations"
	_ "modernc.org/sqlite"
)

func Open(ctx context.Context, directory string) (*sql.DB, error) {
	if err := os.MkdirAll(directory, 0700); err != nil { return nil, err }
	db, err := sql.Open("sqlite", filepath.Join(directory, "obooks.sqlite"))
	if err != nil { return nil, err }
	db.SetMaxOpenConns(1)
	for _, query := range []string{"PRAGMA foreign_keys = ON", "PRAGMA busy_timeout = 5000", "PRAGMA journal_mode = WAL"} {
		if _, err = db.ExecContext(ctx, query); err != nil { db.Close(); return nil, err }
	}
	if err = migrate(ctx, db); err != nil { db.Close(); return nil, err }
	return db, nil
}

func migrate(ctx context.Context, db *sql.DB) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil { return err }
	defer tx.Rollback()
	var version int
	if err = tx.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil { return err }
	if version > 1 { return fmt.Errorf("不支持的数据库版本: %d", version) }
	if version == 0 {
		data, err := migrations.Files.ReadFile("001-initial.sql")
		if err != nil { return err }
		if _, err = tx.ExecContext(ctx, string(data)); err != nil { return err }
		if _, err = tx.ExecContext(ctx, "PRAGMA user_version = 1"); err != nil { return err }
	}
	return tx.Commit()
}
