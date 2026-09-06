package sync

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"regexp"
	"time"
)

var ErrInvalid = errors.New("同步变更无效")
var bookIDPattern = regexp.MustCompile(`^[a-f0-9]{64}$`)
var uuidPattern = regexp.MustCompile(`^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$`)
var tables = map[string]string{"book":"books", "progress":"progress", "bookmark":"bookmarks", "annotation":"annotations", "readingEvent":"reading_events"}

type Change struct {
	DeviceID string `json:"deviceID"`
	ChangeID string `json:"changeID"`
	Entity string `json:"entity"`
	EntityID string `json:"entityID"`
	BookID string `json:"bookID"`
	BaseRevision int64 `json:"baseRevision"`
	Revision int64 `json:"revision"`
	ModifiedAt float64 `json:"modifiedAt"`
	DeletedAt *float64 `json:"deletedAt,omitempty"`
	ConflictOf string `json:"conflictOf,omitempty"`
	Payload json.RawMessage `json:"payload"`
}

type PushResult struct {
	AcceptedIDs []string `json:"acceptedIDs"`
	Conflicts int `json:"conflicts"`
	Cursor int64 `json:"cursor"`
	ServerTime float64 `json:"serverTime"`
}
type PullResult struct {
	Changes []Change `json:"changes"`
	Cursor int64 `json:"cursor"`
	HasMore bool `json:"hasMore"`
	ServerTime float64 `json:"serverTime"`
}
type Service struct { DB *sql.DB }

func ValidBookID(id string) bool { return bookIDPattern.MatchString(id) }

func validate(c Change, deviceID string) error {
	if tables[c.Entity] == "" || !ValidBookID(c.BookID) || !uuidPattern.MatchString(c.ChangeID) || c.DeviceID != deviceID || c.BaseRevision < 0 || c.Revision != 0 || c.ConflictOf != "" { return ErrInvalid }
	if c.Entity == "book" || c.Entity == "progress" {
		if c.EntityID != c.BookID { return ErrInvalid }
	} else if !uuidPattern.MatchString(c.EntityID) { return ErrInvalid }
	if math.IsNaN(c.ModifiedAt) || math.IsInf(c.ModifiedAt, 0) || c.ModifiedAt < 0 || c.ModifiedAt > float64(time.Now().Add(5*time.Minute).Unix()) { return ErrInvalid }
	if c.DeletedAt != nil && (*c.DeletedAt < 0 || *c.DeletedAt > float64(time.Now().Add(5*time.Minute).Unix())) { return ErrInvalid }
	if c.DeletedAt != nil { return nil }
	var payload map[string]json.RawMessage
	if json.Unmarshal(c.Payload, &payload) != nil || payload[c.Entity] == nil { return ErrInvalid }
	if c.Entity == "annotation" || c.Entity == "bookmark" || c.Entity == "readingEvent" {
		var item struct { ID string `json:"id"` }
		if json.Unmarshal(payload[c.Entity], &item) != nil || item.ID != c.EntityID { return ErrInvalid }
	}
	if c.Entity == "progress" {
		var p struct { Fraction float64 `json:"fraction"` }
		if json.Unmarshal(payload[c.Entity], &p) != nil || p.Fraction < 0 || p.Fraction > 1 { return ErrInvalid }
	}
	if c.Entity == "readingEvent" {
		var e struct { Seconds float64 `json:"seconds"`; Hour int `json:"hour"`; Day struct { Year, Month, Day int } `json:"day"` }
		if json.Unmarshal(payload[c.Entity], &e) != nil || e.Seconds <= 0 || e.Hour < 0 || e.Hour > 23 || e.Day.Year < 1970 || e.Day.Year > 9999 || e.Day.Month < 1 || e.Day.Month > 12 || e.Day.Day < 1 || e.Day.Day > 31 { return ErrInvalid }
	}
	return nil
}

func read(ctx context.Context, tx *sql.Tx, userID, entity, id string) (*Change, error) {
	var data []byte
	err := tx.QueryRowContext(ctx, "SELECT document FROM "+tables[entity]+" WHERE user_id=? AND entity_id=?", userID, id).Scan(&data)
	if errors.Is(err, sql.ErrNoRows) { return nil, nil }
	if err != nil { return nil, err }
	var c Change
	if err = json.Unmarshal(data, &c); err != nil { return nil, err }
	return &c, nil
}

func write(ctx context.Context, tx *sql.Tx, userID string, c Change) error {
	result, err := tx.ExecContext(ctx, "INSERT INTO changes(user_id, document) VALUES(?, ?)", userID, []byte("{}"))
	if err != nil { return err }
	c.Revision, err = result.LastInsertId()
	if err != nil { return err }
	data, err := json.Marshal(c)
	if err != nil { return err }
	if _, err = tx.ExecContext(ctx, "UPDATE changes SET document=? WHERE sequence=?", data, c.Revision); err != nil { return err }
	_, err = tx.ExecContext(ctx, "INSERT INTO "+tables[c.Entity]+`(user_id, entity_id, book_id, revision, document) VALUES(?, ?, ?, ?, ?)
        ON CONFLICT(user_id, entity_id) DO UPDATE SET revision=excluded.revision, document=excluded.document`, userID, c.EntityID, c.BookID, c.Revision, data)
	return err
}

func newer(a, b Change) bool {
	if a.ModifiedAt != b.ModifiedAt { return a.ModifiedAt > b.ModifiedAt }
	if a.DeviceID != b.DeviceID { return a.DeviceID > b.DeviceID }
	return a.ChangeID > b.ChangeID
}

func (s *Service) Push(ctx context.Context, userID, deviceID string, changes []Change) (PushResult, error) {
	result := PushResult{AcceptedIDs: []string{}, ServerTime: float64(time.Now().UnixMilli())/1000}
	if len(changes) > 200 { return result, ErrInvalid }
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil { return result, err }
	defer tx.Rollback()
	for _, incoming := range changes {
		if err = validate(incoming, deviceID); err != nil { return result, err }
		data, _ := json.Marshal(incoming)
		digest := sha256.Sum256(data)
		digestString := hex.EncodeToString(digest[:])
		var prior string
		err = tx.QueryRowContext(ctx, "SELECT digest FROM accepted_changes WHERE user_id=? AND change_id=?", userID, incoming.ChangeID).Scan(&prior)
		if err == nil {
			if prior != digestString { return result, ErrInvalid }
			result.AcceptedIDs = append(result.AcceptedIDs, incoming.ChangeID)
			continue
		}
		if !errors.Is(err, sql.ErrNoRows) { return result, err }
		current, err := read(ctx, tx, userID, incoming.Entity, incoming.EntityID)
		if err != nil { return result, err }
		if current != nil && current.BookID != incoming.BookID { return result, ErrInvalid }
		if (current == nil && incoming.BaseRevision != 0) || (current != nil && incoming.BaseRevision > current.Revision) { return result, ErrInvalid }
		apply := true
		if incoming.Entity != "book" {
			parent, err := read(ctx, tx, userID, "book", incoming.BookID)
			if err != nil { return result, err }
			if parent == nil { return result, ErrInvalid }
			if parent.DeletedAt != nil { apply = false }
		}
		if current != nil {
			switch {
			case current.DeletedAt != nil:
				// 只有显式基于当前版本重新导入图书, 才能恢复图书身份.
				apply = apply && incoming.Entity == "book" && incoming.DeletedAt == nil && incoming.BaseRevision == current.Revision
			case incoming.DeletedAt != nil:
			case incoming.Entity == "readingEvent":
				apply = false
			case incoming.Entity == "annotation" && incoming.BaseRevision != current.Revision && apply:
				var oldPayload, newPayload any
				json.Unmarshal(current.Payload, &oldPayload)
				json.Unmarshal(incoming.Payload, &newPayload)
				oldJSON, _ := json.Marshal(oldPayload)
				newJSON, _ := json.Marshal(newPayload)
				if string(oldJSON) == string(newJSON) { apply = false; break }
				originalID := incoming.EntityID
				hash := sha256.Sum256([]byte(userID + incoming.ChangeID))
				id := fmt.Sprintf("%x-%x-%x-%x-%x", hash[:4], hash[4:6], hash[6:8], hash[8:10], hash[10:16])
				var payload map[string]json.RawMessage
				if err = json.Unmarshal(incoming.Payload, &payload); err != nil { return result, err }
				var annotation map[string]any
				if err = json.Unmarshal(payload["annotation"], &annotation); err != nil { return result, err }
				annotation["id"] = id
				annotation["conflictOf"] = originalID
				payload["annotation"], _ = json.Marshal(annotation)
				incoming.Payload, _ = json.Marshal(payload)
				incoming.EntityID, incoming.ConflictOf = id, originalID
				result.Conflicts++
			default:
				apply = apply && newer(incoming, *current)
			}
		}
		if apply {
			if err = write(ctx, tx, userID, incoming); err != nil { return result, err }
			if incoming.Entity == "book" && incoming.DeletedAt != nil {
				if err = deleteChildren(ctx, tx, userID, incoming); err != nil { return result, err }
			}
		}
		if _, err = tx.ExecContext(ctx, "INSERT INTO accepted_changes(user_id, change_id, digest) VALUES(?, ?, ?)", userID, incoming.ChangeID, digestString); err != nil { return result, err }
		result.AcceptedIDs = append(result.AcceptedIDs, incoming.ChangeID)
	}
	if err = tx.QueryRowContext(ctx, "SELECT COALESCE(MAX(sequence), 0) FROM changes WHERE user_id=?", userID).Scan(&result.Cursor); err != nil { return result, err }
	return result, tx.Commit()
}

func deleteChildren(ctx context.Context, tx *sql.Tx, userID string, parent Change) error {
	for _, entity := range []string{"progress", "bookmark", "annotation", "readingEvent"} {
		rows, err := tx.QueryContext(ctx, "SELECT document FROM "+tables[entity]+" WHERE user_id=? AND book_id=?", userID, parent.BookID)
		if err != nil { return err }
		children := []Change{}
		for rows.Next() {
			var data []byte
			if err = rows.Scan(&data); err != nil { rows.Close(); return err }
			var child Change
			if err = json.Unmarshal(data, &child); err != nil { rows.Close(); return err }
			if child.DeletedAt == nil { children = append(children, child) }
		}
		err = rows.Err(); rows.Close()
		if err != nil { return err }
		for _, child := range children {
			child.DeletedAt, child.ModifiedAt, child.DeviceID, child.ChangeID = parent.DeletedAt, parent.ModifiedAt, parent.DeviceID, parent.ChangeID
			if err = write(ctx, tx, userID, child); err != nil { return err }
		}
	}
	return nil
}

func (s *Service) Pull(ctx context.Context, userID, deviceID string, cursor int64) (PullResult, error) {
	result := PullResult{Changes: []Change{}, Cursor: cursor, ServerTime: float64(time.Now().UnixMilli())/1000}
	if cursor < 0 { return result, ErrInvalid }
	var maximum int64
	if err := s.DB.QueryRowContext(ctx, "SELECT COALESCE(MAX(sequence), 0) FROM changes WHERE user_id=?", userID).Scan(&maximum); err != nil { return result, err }
	if cursor > maximum { return result, ErrInvalid }
	rows, err := s.DB.QueryContext(ctx, "SELECT sequence, document FROM changes WHERE user_id=? AND sequence>? ORDER BY sequence LIMIT 201", userID, cursor)
	if err != nil { return result, err }
	defer rows.Close()
	for rows.Next() {
		if len(result.Changes) == 200 { result.HasMore = true; break }
		var data []byte
		if err = rows.Scan(&result.Cursor, &data); err != nil { return result, err }
		var c Change
		if err = json.Unmarshal(data, &c); err != nil { return result, err }
		result.Changes = append(result.Changes, c)
	}
	if err = rows.Err(); err != nil { return result, err }
	rows.Close()
	// 请求中的游标才是客户端已持久化确认的位置.
	_, err = s.DB.ExecContext(ctx, "UPDATE devices SET cursor=MAX(cursor, ?), last_seen=? WHERE user_id=? AND id=?", cursor, time.Now().Unix(), userID, deviceID)
	return result, err
}

func (s *Service) BookExists(ctx context.Context, userID, bookID string) bool {
	if !ValidBookID(bookID) { return false }
	var data []byte
	if s.DB.QueryRowContext(ctx, "SELECT document FROM books WHERE user_id=? AND entity_id=?", userID, bookID).Scan(&data) != nil { return false }
	var c Change
	return json.Unmarshal(data, &c) == nil && c.DeletedAt == nil
}
