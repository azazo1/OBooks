package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"golang.org/x/crypto/argon2"
)

var ErrUnauthorized = errors.New("账号, 密码或会话无效")

type Service struct {
	DB *sql.DB
	AccessTTL time.Duration
	RefreshTTL time.Duration
}

type Identity struct { UserID, DeviceID string }
type Tokens struct {
	UserID string `json:"userID"`
	AccessToken string `json:"accessToken"`
	RefreshToken string `json:"refreshToken"`
	ExpiresIn int64 `json:"expiresIn"`
	ServerTime float64 `json:"serverTime"`
}

func RandomID() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil { panic(err) }
	return base64.RawURLEncoding.EncodeToString(b)
}

func hashToken(token string) string {
	digest := sha256.Sum256([]byte(token))
	return hex.EncodeToString(digest[:])
}

func hashPassword(password string) (string, error) {
	if len(password) < 12 || len(password) > 1024 { return "", errors.New("密码长度必须在 12 到 1024 字节之间") }
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil { return "", err }
	key := argon2.IDKey([]byte(password), salt, 3, 64*1024, 2, 32)
	return "$argon2id$v=19$m=65536,t=3,p=2$" + base64.RawStdEncoding.EncodeToString(salt) + "$" + base64.RawStdEncoding.EncodeToString(key), nil
}

func verifyPassword(encoded, password string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" || parts[2] != "v=19" || parts[3] != "m=65536,t=3,p=2" { return false }
	salt, e1 := base64.RawStdEncoding.DecodeString(parts[4])
	expected, e2 := base64.RawStdEncoding.DecodeString(parts[5])
	if e1 != nil || e2 != nil || len(salt) != 16 || len(expected) != 32 { return false }
	key := argon2.IDKey([]byte(password), salt, 3, 64*1024, 2, 32)
	return subtle.ConstantTimeCompare(key, expected) == 1
}

func (s *Service) CreateUser(ctx context.Context, username, password string) error {
	if strings.TrimSpace(username) != username || len(username) < 1 || len(username) > 100 { return errors.New("用户名无效") }
	hash, err := hashPassword(password)
	if err != nil { return err }
	_, err = s.DB.ExecContext(ctx, "INSERT INTO users(id, username, password_hash) VALUES(?, ?, ?)", RandomID(), username, hash)
	return err
}

func (s *Service) UpdateUser(ctx context.Context, username, password string, disable bool) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil { return err }
	defer tx.Rollback()
	var id string
	if err = tx.QueryRowContext(ctx, "SELECT id FROM users WHERE username = ?", username).Scan(&id); err != nil { return err }
	if disable {
		_, err = tx.ExecContext(ctx, "UPDATE users SET disabled = 1 WHERE id = ?", id)
	} else {
		var hash string
		hash, err = hashPassword(password)
		if err == nil { _, err = tx.ExecContext(ctx, "UPDATE users SET password_hash = ?, disabled = 0 WHERE id = ?", hash, id) }
	}
	if err != nil { return err }
	if _, err = tx.ExecContext(ctx, "DELETE FROM sessions WHERE user_id = ?", id); err != nil { return err }
	return tx.Commit()
}

func (s *Service) Login(ctx context.Context, username, password, deviceID, deviceName string) (Tokens, error) {
	if len(password) > 1024 || len(username) > 100 || len(deviceID) < 1 || len(deviceID) > 100 || len(deviceName) > 200 { return Tokens{}, ErrUnauthorized }
	var id, hash string
	err := s.DB.QueryRowContext(ctx, "SELECT id, password_hash FROM users WHERE username = ? AND disabled = 0", username).Scan(&id, &hash)
	if err != nil || !verifyPassword(hash, password) { return Tokens{}, ErrUnauthorized }
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil { return Tokens{}, err }
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, `INSERT INTO devices(user_id, id, name, last_seen) VALUES(?, ?, ?, ?)
        ON CONFLICT(user_id, id) DO UPDATE SET name=excluded.name, last_seen=excluded.last_seen`, id, deviceID, deviceName, time.Now().Unix())
	if err != nil { return Tokens{}, err }
	// 同一设备重新登录时撤销旧会话.
	if _, err = tx.ExecContext(ctx, "DELETE FROM sessions WHERE user_id = ? AND device_id = ?", id, deviceID); err != nil { return Tokens{}, err }
	tokens, err := s.issue(ctx, tx, id, deviceID)
	if err != nil { return Tokens{}, err }
	return tokens, tx.Commit()
}

func (s *Service) issue(ctx context.Context, tx *sql.Tx, userID, deviceID string) (Tokens, error) {
	now := time.Now()
	tokens := Tokens{userID, RandomID(), RandomID(), int64(s.AccessTTL.Seconds()), float64(now.UnixMilli()) / 1000}
	_, err := tx.ExecContext(ctx, `INSERT INTO sessions(refresh_hash, access_hash, user_id, device_id, access_expires, refresh_expires)
        VALUES(?, ?, ?, ?, ?, ?)`, hashToken(tokens.RefreshToken), hashToken(tokens.AccessToken), userID, deviceID, now.Add(s.AccessTTL).Unix(), now.Add(s.RefreshTTL).Unix())
	return tokens, err
}

func (s *Service) Refresh(ctx context.Context, token string) (Tokens, error) {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil { return Tokens{}, err }
	defer tx.Rollback()
	var userID, deviceID string
	err = tx.QueryRowContext(ctx, `SELECT s.user_id, s.device_id FROM sessions s JOIN users u ON u.id=s.user_id
        WHERE s.refresh_hash=? AND s.refresh_expires>? AND u.disabled=0`, hashToken(token), time.Now().Unix()).Scan(&userID, &deviceID)
	if err != nil { return Tokens{}, ErrUnauthorized }
	if _, err = tx.ExecContext(ctx, "DELETE FROM sessions WHERE refresh_hash=?", hashToken(token)); err != nil { return Tokens{}, err }
	tokens, err := s.issue(ctx, tx, userID, deviceID)
	if err != nil { return Tokens{}, err }
	return tokens, tx.Commit()
}

func (s *Service) Authenticate(ctx context.Context, token string) (Identity, error) {
	var id Identity
	err := s.DB.QueryRowContext(ctx, `SELECT s.user_id, s.device_id FROM sessions s JOIN users u ON u.id=s.user_id
        WHERE s.access_hash=? AND s.access_expires>? AND u.disabled=0`, hashToken(token), time.Now().Unix()).Scan(&id.UserID, &id.DeviceID)
	if err != nil { return id, ErrUnauthorized }
	return id, nil
}

func (s *Service) Logout(ctx context.Context, token string) error {
	_, err := s.DB.ExecContext(ctx, "DELETE FROM sessions WHERE refresh_hash=?", hashToken(token))
	return err
}
