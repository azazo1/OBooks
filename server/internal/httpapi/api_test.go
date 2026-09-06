package httpapi

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"obooks/server/internal/auth"
	"obooks/server/internal/library"
	"obooks/server/internal/storage"
	syncservice "obooks/server/internal/sync"
)

const device = "00000000-0000-0000-0000-000000000001"
const book = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

type fixture struct { api *API; handler http.Handler; tokens auth.Tokens; directory string }

func setup(t *testing.T) *fixture {
	t.Helper()
	directory := t.TempDir()
	db, err := storage.Open(context.Background(), directory)
	if err != nil { t.Fatal(err) }
	t.Cleanup(func() { db.Close() })
	a := &auth.Service{DB:db, AccessTTL:15*time.Minute, RefreshTTL:24*time.Hour}
	if err = a.CreateUser(context.Background(), "alice", "a-long-test-password"); err != nil { t.Fatal(err) }
	api := &API{Auth:a, Sync:&syncservice.Service{DB:db}, Files:&library.Store{DB:db, Root:filepath.Join(directory, "objects")}, Logger:slog.New(slog.NewTextHandler(io.Discard, nil))}
	f := &fixture{api:api, handler:api.Handler(), directory:directory}
	response := f.call("POST", "/v1/auth/login", "", map[string]string{"username":"alice", "password":"a-long-test-password", "deviceID":device, "deviceName":"A"})
	f.decode(t, response, 200, &f.tokens)
	return f
}

func (f *fixture) call(method, path, token string, body any) *httptest.ResponseRecorder {
	var reader io.Reader
	if body != nil { data, _ := json.Marshal(body); reader = bytes.NewReader(data) }
	r := httptest.NewRequest(method, path, reader)
	if token != "" { r.Header.Set("Authorization", "Bearer "+token) }
	w := httptest.NewRecorder()
	f.handler.ServeHTTP(w, r)
	return w
}

func (f *fixture) decode(t *testing.T, w *httptest.ResponseRecorder, status int, value any) {
	t.Helper()
	if w.Code != status { t.Fatalf("status=%d, expected=%d: %s", w.Code, status, w.Body) }
	if value != nil { if err := json.Unmarshal(w.Body.Bytes(), value); err != nil { t.Fatal(err) } }
}

func change(entity, id, changeID string, payload string) syncservice.Change {
	return syncservice.Change{DeviceID:device, ChangeID:changeID, Entity:entity, EntityID:id, BookID:book, ModifiedAt:1000, Payload:json.RawMessage(payload)}
}

func bookChange() syncservice.Change {
	return change("book", book, "00000000-0000-0000-0000-000000000010", `{"book":{"title":"Book","authors":[],"sortTitle":"book","sourceFileName":"book.epub","spine":[],"toc":[],"importedAt":1000,"isFinished":false,"isHiddenFromContinueReading":false}}`)
}

func (f *fixture) push(t *testing.T, changes ...syncservice.Change) syncservice.PushResult {
	t.Helper()
	var response syncservice.PushResult
	f.decode(t, f.call("POST", "/v1/sync/push", f.tokens.AccessToken, map[string]any{"changes":changes}), 200, &response)
	return response
}

func (f *fixture) pull(t *testing.T, cursor string) syncservice.PullResult {
	t.Helper()
	var response syncservice.PullResult
	f.decode(t, f.call("GET", "/v1/sync/pull?cursor="+cursor, f.tokens.AccessToken, nil), 200, &response)
	return response
}

func TestAuthRotationDisableAndIsolation(t *testing.T) {
	f := setup(t)
	f.decode(t, f.call("GET", "/v1/sync/pull?cursor=0", "", nil), 401, nil)
	f.decode(t, f.call("POST", "/v1/auth/login", "", map[string]string{"username":"alice", "password":"wrong", "deviceID":device}), 401, nil)
	f.push(t, bookChange())
	if err := f.api.Auth.CreateUser(context.Background(), "bob", "another-long-password"); err != nil { t.Fatal(err) }
	other, err := f.api.Auth.Login(context.Background(), "bob", "another-long-password", "other", "B")
	if err != nil { t.Fatal(err) }
	var empty syncservice.PullResult
	f.decode(t, f.call("GET", "/v1/sync/pull?cursor=0", other.AccessToken, nil), 200, &empty)
	if len(empty.Changes) != 0 { t.Fatal("跨账号数据泄露") }
	f.decode(t, f.call("GET", "/v1/books/"+book+"/content", other.AccessToken, nil), 404, nil)
	var refreshed auth.Tokens
	f.decode(t, f.call("POST", "/v1/auth/refresh", "", map[string]string{"refreshToken":f.tokens.RefreshToken}), 200, &refreshed)
	f.decode(t, f.call("POST", "/v1/auth/refresh", "", map[string]string{"refreshToken":f.tokens.RefreshToken}), 401, nil)
	f.decode(t, f.call("GET", "/v1/sync/pull?cursor=0", f.tokens.AccessToken, nil), 401, nil)
	f.decode(t, f.call("GET", "/v1/sync/pull?cursor=0", refreshed.AccessToken, nil), 200, nil)
	if err = f.api.Auth.UpdateUser(context.Background(), "alice", "", true); err != nil { t.Fatal(err) }
	f.decode(t, f.call("GET", "/v1/sync/pull?cursor=0", refreshed.AccessToken, nil), 401, nil)
	if err = f.api.Auth.UpdateUser(context.Background(), "alice", "replacement-password", false); err != nil { t.Fatal(err) }
	newTokens, err := f.api.Auth.Login(context.Background(), "alice", "replacement-password", device, "A")
	if err != nil { t.Fatal(err) }
	f.decode(t, f.call("POST", "/v1/auth/logout", "", map[string]string{"refreshToken":newTokens.RefreshToken}), 204, nil)
	f.decode(t, f.call("GET", "/v1/sync/pull?cursor=0", newTokens.AccessToken, nil), 401, nil)
}

func TestIdempotenceProgressConflictAndDeletion(t *testing.T) {
	f := setup(t)
	first := bookChange()
	f.push(t, first)
	f.push(t, first)
	if len(f.pull(t, "0").Changes) != 1 { t.Fatal("重试产生重复变更") }
	progress := change("progress", book, "00000000-0000-0000-0000-000000000011", `{"progress":{"fraction":0.8}}`)
	progress.ModifiedAt = 2000
	f.push(t, progress)
	older := progress
	older.ChangeID = "00000000-0000-0000-0000-000000000012"
	older.ModifiedAt = 1500
	older.Payload = json.RawMessage(`{"progress":{"fraction":0.1}}`)
	f.push(t, older)
	if len(f.pull(t, "0").Changes) != 2 { t.Fatal("旧阅读进度覆盖新进度") }
	annotationID := "ABCDEFAB-0000-0000-0000-000000000020"
	note := change("annotation", annotationID, "00000000-0000-0000-0000-000000000013", `{"annotation":{"id":"`+annotationID+`","text":"A","kind":"note","sectionIndex":0,"range":[0,1]}}`)
	f.push(t, note)
	concurrent := note
	concurrent.EntityID = strings.ToLower(annotationID)
	concurrent.ChangeID = "00000000-0000-0000-0000-000000000014"
	concurrent.Payload = json.RawMessage(`{"annotation":{"id":"`+annotationID+`","text":"B","kind":"note","sectionIndex":0,"range":[0,1]}}`)
	if f.push(t, concurrent).Conflicts != 1 { t.Fatal("并发编辑未保留副本") }
	if f.push(t, concurrent).Conflicts != 0 { t.Fatal("重试重复创建副本") }
	page := f.pull(t, "0")
	if len(page.Changes) != 4 || page.Changes[3].ConflictOf != strings.ToLower(annotationID) { t.Fatal("冲突记录无效") }
	deleted := first
	deleted.ChangeID = "00000000-0000-0000-0000-000000000015"
	deleted.ModifiedAt = 3000
	deleted.DeletedAt = &deleted.ModifiedAt
	f.push(t, deleted)
	oldCount := len(f.pull(t, "0").Changes)
	stale := note
	stale.ChangeID = "00000000-0000-0000-0000-000000000016"
	stale.ModifiedAt = 4000
	f.push(t, stale)
	if len(f.pull(t, "0").Changes) != oldCount { t.Fatal("已删除图书被旧设备复活") }
	if f.api.Sync.BookExists(context.Background(), f.tokens.UserID, book) { t.Fatal("已删除图书仍可下载") }
}

func TestReadingEventsAndCursorPagination(t *testing.T) {
	f := setup(t)
	f.push(t, bookChange())
	for page := 0; page < 3; page++ {
		batch := []syncservice.Change{}
		for i := 0; i < 100; i++ {
			id := uuid(page*100+i+100)
			c := change("readingEvent", id, uuid(page*100+i+1000), `{"readingEvent":{"id":"`+id+`","day":{"year":2026,"month":9,"day":6},"hour":10,"seconds":15}}`)
			batch = append(batch, c)
		}
		f.push(t, batch...)
		f.push(t, batch...)
	}
	first := f.pull(t, "0")
	if len(first.Changes) != 200 || !first.HasMore { t.Fatal("分页大小无效") }
	second, err := f.api.Sync.Pull(context.Background(), f.tokens.UserID, device, first.Cursor)
	if err != nil || len(second.Changes) != 101 || second.HasMore { t.Fatalf("分页丢失变更: %+v %v", second, err) }
	var total float64
	for _, c := range append(first.Changes, second.Changes...) {
		if c.Entity == "readingEvent" { var p struct { ReadingEvent struct { Seconds float64 } }; json.Unmarshal(c.Payload, &p); total += p.ReadingEvent.Seconds }
	}
	if total != 4500 { t.Fatalf("时长重复: %v", total) }
	f.decode(t, f.call("GET", "/v1/sync/pull?cursor=999999", f.tokens.AccessToken, nil), 409, nil)
}

func uuid(n int) string { return fmt.Sprintf("00000000-0000-0000-0000-%012d", n) }

func TestFileFingerprintUploadRangeAndValidation(t *testing.T) {
	f := setup(t)
	archivePath := filepath.Join(f.directory, "book.epub")
	var buffer bytes.Buffer
	w := zip.NewWriter(&buffer)
	for _, entry := range []struct { Name, Content string }{{"mimetype", "application/epub+zip"}, {"META-INF/container.xml", "<container/>"}, {"chapter.xhtml", "<p>hello</p>"}} {
		entryWriter, err := w.Create(entry.Name)
		if err != nil { t.Fatal(err) }
		io.WriteString(entryWriter, entry.Content)
	}
	w.Close()
	if err := os.WriteFile(archivePath, buffer.Bytes(), 0600); err != nil { t.Fatal(err) }
	id, err := library.Fingerprint(archivePath)
	if err != nil { t.Fatal(err) }
	c := bookChange(); c.BookID = id; c.EntityID = id
	f.push(t, c)
	request := httptest.NewRequest("PUT", "/v1/books/"+id+"/content", bytes.NewReader(buffer.Bytes()))
	request.Header.Set("Authorization", "Bearer "+f.tokens.AccessToken)
	response := httptest.NewRecorder(); f.handler.ServeHTTP(response, request)
	f.decode(t, response, 204, nil)
	request = httptest.NewRequest("GET", "/v1/books/"+id+"/content", nil)
	request.Header.Set("Authorization", "Bearer "+f.tokens.AccessToken)
	request.Header.Set("Range", "bytes=0-9")
	response = httptest.NewRecorder(); f.handler.ServeHTTP(response, request)
	if response.Code != 206 || !bytes.Equal(response.Body.Bytes(), buffer.Bytes()[:10]) { t.Fatal("Range 下载失败") }
	f.decode(t, f.call("PUT", "/v1/books/"+id+"/content", f.tokens.AccessToken, "not an epub"), 400, nil)
	first := bookChange(); first.ChangeID = uuid(9999)
	f.push(t, first)
	request = httptest.NewRequest("PUT", "/v1/books/"+book+"/content", bytes.NewReader(buffer.Bytes()))
	request.Header.Set("Authorization", "Bearer "+f.tokens.AccessToken)
	response = httptest.NewRecorder(); f.handler.ServeHTTP(response, request)
	f.decode(t, response, 400, nil)
}

func TestInvalidPayloadAndAtomicBatch(t *testing.T) {
	f := setup(t)
	c := bookChange()
	invalid := c; invalid.ChangeID = "invalid"
	f.decode(t, f.call("POST", "/v1/sync/push", f.tokens.AccessToken, map[string]any{"changes":[]syncservice.Change{c, invalid}}), 400, nil)
	if len(f.pull(t, "0").Changes) != 0 { t.Fatal("无效批次未回滚") }
	f.push(t, c)
	c.Payload = json.RawMessage(`{"book":{"title":"different"}}`)
	f.decode(t, f.call("POST", "/v1/sync/push", f.tokens.AccessToken, map[string]any{"changes":[]syncservice.Change{c}}), 400, nil)
	r := httptest.NewRequest("POST", "/v1/auth/login", strings.NewReader(`{"username":"`+strings.Repeat("x", 9000)+`"}`))
	w := httptest.NewRecorder(); f.handler.ServeHTTP(w, r)
	f.decode(t, w, 413, nil)
}

func TestSwiftClientIntegration(t *testing.T) {
	if os.Getenv("OBOOKS_RUN_SWIFT_INTEGRATION") != "1" { t.Skip("通过 just sync-integration 执行 Swift 与 Go 联调") }
	f := setup(t)
	server := httptest.NewServer(f.handler)
	defer server.Close()
	root, err := filepath.Abs("../../..")
	if err != nil { t.Fatal(err) }
	command := exec.Command("swift", "test", "--skip-build", "--filter", "SyncTransportTests.testLive")
	command.Dir = root
	command.Env = append(os.Environ(), "OBOOKS_SYNC_TEST_URL="+server.URL)
	output, err := command.CombinedOutput()
	if err != nil { t.Fatalf("Swift 联调失败: %v\n%s", err, output) }
	t.Log(string(output))
}

func TestGarbageCollectionRequiresEveryDeviceAcknowledgement(t *testing.T) {
	f := setup(t)
	_, err := f.api.Auth.Login(context.Background(), "alice", "a-long-test-password", "offline-device", "B")
	if err != nil { t.Fatal(err) }
	c := bookChange()
	f.push(t, c)
	c.ChangeID = uuid(9998)
	c.DeletedAt = &c.ModifiedAt
	f.push(t, c)
	page := f.pull(t, "0")
	_, err = f.api.Sync.Pull(context.Background(), f.tokens.UserID, device, page.Cursor)
	if err != nil { t.Fatal(err) }
	count, err := f.api.Files.Prune(context.Background(), 30*24*time.Hour)
	if err != nil || count != 0 { t.Fatalf("设备尚未确认就清理: %d %v", count, err) }
	_, err = f.api.Sync.Pull(context.Background(), f.tokens.UserID, "offline-device", page.Cursor)
	if err != nil { t.Fatal(err) }
	count, err = f.api.Files.Prune(context.Background(), 30*24*time.Hour)
	if err != nil || count != 1 { t.Fatalf("文件回收失败: %d %v", count, err) }
	if len(f.pull(t, "0").Changes) != 2 { t.Fatal("墓碑被清理, 新设备可能复活旧数据") }
}
