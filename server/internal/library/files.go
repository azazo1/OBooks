package library

import (
	"archive/zip"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
)

const MaxUpload = 512 << 20
const MaxCover = 10 << 20
var ErrInvalid = errors.New("EPUB 文件或内容指纹无效")

type Store struct { DB *sql.DB; Root string }

// Fingerprint 按路径排序后对文件清单哈希, 忽略 ZIP 压缩元信息.
func Fingerprint(filename string) (string, error) {
	r, err := zip.OpenReader(filename)
	if err != nil { return "", ErrInvalid }
	defer r.Close()
	files := append([]*zip.File(nil), r.File...)
	if len(files) > 50000 { return "", ErrInvalid }
	sort.Slice(files, func(i, j int) bool { return files[i].Name < files[j].Name })
	manifest := sha256.New()
	var total uint64
	var previous string
	var mimetype, container bool
	for _, file := range files {
		name := file.Name
		if strings.HasPrefix(name, "/") || strings.Contains(name, "\\") || strings.ContainsRune(name, 0) || path.Clean(name) != strings.TrimSuffix(name, "/") || file.Mode() & os.ModeSymlink != 0 { return "", ErrInvalid }
		if name == ".." || strings.HasPrefix(name, "../") { return "", ErrInvalid }
		if file.FileInfo().IsDir() { continue }
		if name == previous || file.UncompressedSize64 > 256<<20 { return "", ErrInvalid }
		previous = name
		total += file.UncompressedSize64
		if total > 1<<30 { return "", ErrInvalid }
		reader, err := file.Open()
		if err != nil { return "", ErrInvalid }
		hash := sha256.New()
		n, copyErr := io.Copy(hash, io.LimitReader(reader, int64(file.UncompressedSize64)+1))
		reader.Close()
		if copyErr != nil || uint64(n) != file.UncompressedSize64 { return "", ErrInvalid }
		if name == "mimetype" {
			expected := sha256.Sum256([]byte("application/epub+zip"))
			mimetype = hex.EncodeToString(hash.Sum(nil)) == hex.EncodeToString(expected[:])
		}
		if name == "META-INF/container.xml" { container = true }
		fmt.Fprintf(manifest, "%s%c%d%c", name, 0, n, 0)
		manifest.Write(hash.Sum(nil))
	}
	if !mimetype || !container { return "", ErrInvalid }
	return hex.EncodeToString(manifest.Sum(nil)), nil
}

func (s *Store) Put(ctx context.Context, userID, bookID, kind string, reader io.Reader) error {
	directory := filepath.Join(s.Root, userID, bookID)
	if err := os.MkdirAll(directory, 0700); err != nil { return err }
	file, err := os.CreateTemp(directory, ".upload-")
	if err != nil { return err }
	defer os.Remove(file.Name())
	hash := sha256.New()
	limit := int64(MaxUpload)
	if kind == "cover" { limit = MaxCover }
	n, err := io.Copy(io.MultiWriter(file, hash), io.LimitReader(reader, limit+1))
	if err != nil { file.Close(); return err }
	if n > limit || n == 0 { file.Close(); return ErrInvalid }
	if err = file.Sync(); err != nil { file.Close(); return err }
	if err = file.Close(); err != nil { return err }
	if kind == "content" {
		id, err := Fingerprint(file.Name())
		if err != nil || id != bookID { return ErrInvalid }
	} else {
		f, err := os.Open(file.Name())
		if err != nil { return err }
		var signature [8]byte
		_, err = io.ReadFull(f, signature[:]); f.Close()
		if err != nil || string(signature[:]) != "\x89PNG\r\n\x1a\n" { return ErrInvalid }
	}
	digest := hex.EncodeToString(hash.Sum(nil))
	// 内容寻址文件先落盘, 数据库再发布引用, 失败时不会破坏旧文件.
	if err = os.Rename(file.Name(), filepath.Join(directory, digest)); err != nil { return err }
	_, err = s.DB.ExecContext(ctx, `INSERT INTO files(user_id, book_id, kind, digest, size) VALUES(?, ?, ?, ?, ?)
        ON CONFLICT(user_id, book_id, kind) DO UPDATE SET digest=excluded.digest, size=excluded.size`, userID, bookID, kind, digest, n)
	return err
}

func (s *Store) Get(ctx context.Context, userID, bookID, kind string) (string, string, error) {
	var digest string
	if err := s.DB.QueryRowContext(ctx, "SELECT digest FROM files WHERE user_id=? AND book_id=? AND kind=?", userID, bookID, kind).Scan(&digest); err != nil { return "", "", err }
	return filepath.Join(s.Root, userID, bookID, digest), digest, nil
}
