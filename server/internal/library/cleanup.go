package library

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

// Prune 只回收超过保留期且所有设备均已确认删除的文件, 墓碑和幂等记录持续保留.
func (s *Store) Prune(ctx context.Context, retention time.Duration) (int, error) {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil { return 0, err }
	defer tx.Rollback()
	rows, err := tx.QueryContext(ctx, `SELECT b.user_id, b.book_id, b.document, b.revision,
        COALESCE((SELECT MIN(cursor) FROM devices WHERE user_id=b.user_id),0) FROM books b`)
	if err != nil { return 0, err }
	type candidate struct { userID, bookID string }
	var candidates []candidate
	for rows.Next() {
		var item candidate
		var data []byte
		var revision, acknowledged int64
		if err = rows.Scan(&item.userID, &item.bookID, &data, &revision, &acknowledged); err != nil { rows.Close(); return 0, err }
		var document struct { DeletedAt *float64 `json:"deletedAt"` }
		if err = json.Unmarshal(data, &document); err != nil { rows.Close(); return 0, err }
		if document.DeletedAt != nil && *document.DeletedAt <= float64(time.Now().Add(-retention).Unix()) && acknowledged >= revision {
			candidates = append(candidates, item)
		}
	}
	err = rows.Err(); rows.Close()
	if err != nil { return 0, err }
	for _, item := range candidates {
		if _, err = tx.ExecContext(ctx, "DELETE FROM files WHERE user_id=? AND book_id=?", item.userID, item.bookID); err != nil { return 0, err }
		if err = os.RemoveAll(filepath.Join(s.Root, item.userID, item.bookID)); err != nil { return 0, err }
	}
	return len(candidates), tx.Commit()
}
