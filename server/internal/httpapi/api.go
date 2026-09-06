package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"obooks/server/internal/auth"
	"obooks/server/internal/library"
	syncservice "obooks/server/internal/sync"
)

type API struct {
	Auth *auth.Service
	Sync *syncservice.Service
	Files *library.Store
	Logger *slog.Logger
	logins *attemptLimiter
	errors *attemptLimiter
	loginSlots chan struct{}
}

func (a *API) Handler() http.Handler {
	if a.logins == nil {
		a.logins = newAttemptLimiter(limiterWindow, loginLimit, limiterMaxKeys)
	}
	if a.errors == nil {
		a.errors = newAttemptLimiter(limiterWindow, errorLimit, limiterMaxKeys)
	}
	if a.loginSlots == nil {
		a.loginSlots = make(chan struct{}, loginConcurrency)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { respond(w, http.StatusOK, map[string]string{"status":"ok"}) })
	mux.HandleFunc("POST /v1/auth/login", a.login)
	mux.HandleFunc("POST /v1/auth/refresh", a.refresh)
	mux.HandleFunc("POST /v1/auth/logout", a.logout)
	mux.HandleFunc("POST /v1/auth/account", a.authorized(a.account))
	mux.HandleFunc("GET /v1/sync/pull", a.authorized(a.pull))
	mux.HandleFunc("POST /v1/sync/push", a.authorized(a.push))
	for _, kind := range []string{"content", "cover"} {
		mux.HandleFunc("GET /v1/books/{bookID}/"+kind, a.authorized(a.getFile(kind)))
		mux.HandleFunc("HEAD /v1/books/{bookID}/"+kind, a.authorized(a.getFile(kind)))
		mux.HandleFunc("PUT /v1/books/{bookID}/"+kind, a.authorized(a.putFile(kind)))
	}
	return a.protect(mux)
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	if w.status == 0 {
		w.status = status
	}
	w.ResponseWriter.WriteHeader(status)
}

func (w *statusWriter) Write(p []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	return w.ResponseWriter.Write(p)
}

func (w *statusWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

func (w *statusWriter) Flush() {
	if f, ok := w.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

func (a *API) protect(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		started := time.Now()
		ip := clientIP(r)
		if r.URL.Path != "/healthz" && a.errors.blocked(ip) {
			limited(w, "请求过于频繁")
			a.Logger.Debug("请求完成", "method", r.Method, "path", r.URL.Path, "status", http.StatusTooManyRequests, "duration", time.Since(started))
			return
		}
		recorder := &statusWriter{ResponseWriter: w}
		next.ServeHTTP(recorder, r)
		if r.URL.Path != "/healthz" && isClientError(recorder.status) {
			if recorded, reached := a.errors.charge(ip); recorded && reached {
				a.Logger.Warn("错误请求过多, 开始限流", "ip", ip, "path", r.URL.Path, "status", recorder.status)
			}
		}
		a.Logger.Debug("请求完成", "method", r.Method, "path", r.URL.Path, "duration", time.Since(started))
	})
}

func respond(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(value)
}

func fail(w http.ResponseWriter, status int, code, message string) {
	respond(w, status, map[string]any{"error":map[string]string{"code":code, "message":message}})
}

func limited(w http.ResponseWriter, message string) {
	w.Header().Set("Retry-After", strconv.Itoa(int(limiterWindow.Seconds())))
	fail(w, http.StatusTooManyRequests, "rate_limited", message)
}

func decode(w http.ResponseWriter, r *http.Request, value any, limit int64) bool {
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(value); err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) { fail(w, 413, "too_large", "请求体过大") } else { fail(w, 400, "invalid_request", "请求格式无效") }
		return false
	}
	if d.Decode(new(any)) != io.EOF { fail(w, 400, "invalid_request", "请求包含多余数据"); return false }
	return true
}

func (a *API) authorized(next func(http.ResponseWriter, *http.Request, auth.Identity)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		prefix, token, ok := strings.Cut(r.Header.Get("Authorization"), " ")
		if !ok || prefix != "Bearer" { fail(w, 401, "unauthorized", "请重新登录"); return }
		id, err := a.Auth.Authenticate(r.Context(), token)
		if err != nil { fail(w, 401, "unauthorized", "请重新登录"); return }
		next(w, r, id)
	}
}

func (a *API) login(w http.ResponseWriter, r *http.Request) {
	if recorded, _ := a.logins.charge(clientIP(r)); !recorded {
		limited(w, "登录请求过于频繁")
		return
	}
	select {
	case a.loginSlots <- struct{}{}: defer func() { <-a.loginSlots }()
	default: limited(w, "登录服务繁忙"); return
	}
	var body struct { Username string `json:"username"`; Password string `json:"password"`; DeviceID string `json:"deviceID"`; DeviceName string `json:"deviceName"` }
	if !decode(w, r, &body, 8<<10) { return }
	tokens, err := a.Auth.Login(r.Context(), body.Username, body.Password, body.DeviceID, body.DeviceName)
	if err != nil { a.Logger.Warn("登录失败"); fail(w, 401, "unauthorized", "账号或密码无效"); return }
	a.Logger.Info("设备登录", "user", tokens.UserID, "device", body.DeviceID)
	respond(w, 200, tokens)
}

func (a *API) refresh(w http.ResponseWriter, r *http.Request) {
	var body struct { RefreshToken string `json:"refreshToken"` }
	if !decode(w, r, &body, 8<<10) { return }
	tokens, err := a.Auth.Refresh(r.Context(), body.RefreshToken)
	if err != nil { fail(w, 401, "unauthorized", "会话已过期, 请重新登录"); return }
	respond(w, 200, tokens)
}

func (a *API) logout(w http.ResponseWriter, r *http.Request) {
	var body struct { RefreshToken string `json:"refreshToken"` }
	if !decode(w, r, &body, 8<<10) { return }
	if err := a.Auth.Logout(r.Context(), body.RefreshToken); err != nil { a.internalError(w, err); return }
	w.WriteHeader(204)
}

func (a *API) account(w http.ResponseWriter, r *http.Request, id auth.Identity) {
	var body struct {
		DeviceName *string `json:"deviceName"`
		CurrentPassword *string `json:"currentPassword"`
		NewPassword *string `json:"newPassword"`
	}
	if !decode(w, r, &body, 8<<10) { return }
	if body.DeviceName == nil && body.NewPassword == nil {
		fail(w, 400, "invalid_request", "没有要更新的账号信息")
		return
	}
	if body.NewPassword != nil {
		if body.CurrentPassword == nil {
			fail(w, 400, "invalid_request", "修改密码需要提供当前密码")
			return
		}
		err := a.Auth.ChangePassword(r.Context(), id, *body.CurrentPassword, *body.NewPassword)
		if errors.Is(err, auth.ErrUnauthorized) { fail(w, 401, "unauthorized", "当前密码不正确"); return }
		if err != nil { fail(w, 400, "invalid_request", err.Error()); return }
		a.Logger.Info("修改密码", "user", id.UserID)
	}
	if body.DeviceName != nil {
		if err := a.Auth.RenameDevice(r.Context(), id, *body.DeviceName); err != nil {
			fail(w, 400, "invalid_request", err.Error())
			return
		}
		a.Logger.Info("更新设备名称", "user", id.UserID, "device", id.DeviceID)
	}
	w.WriteHeader(204)
}

func (a *API) pull(w http.ResponseWriter, r *http.Request, id auth.Identity) {
	cursor, err := strconv.ParseInt(r.URL.Query().Get("cursor"), 10, 64)
	if err != nil { fail(w, 400, "invalid_cursor", "同步游标无效"); return }
	result, err := a.Sync.Pull(r.Context(), id.UserID, id.DeviceID, cursor)
	if errors.Is(err, syncservice.ErrInvalid) { fail(w, 409, "invalid_cursor", "同步游标无效, 请重置同步索引"); return }
	if err != nil { a.internalError(w, err); return }
	a.Logger.Info("拉取变更", "user", id.UserID, "count", len(result.Changes), "cursor", result.Cursor)
	respond(w, 200, result)
}

func (a *API) push(w http.ResponseWriter, r *http.Request, id auth.Identity) {
	var body struct { Changes []syncservice.Change `json:"changes"` }
	if !decode(w, r, &body, 4<<20) { return }
	result, err := a.Sync.Push(r.Context(), id.UserID, id.DeviceID, body.Changes)
	if errors.Is(err, syncservice.ErrInvalid) { fail(w, 400, "invalid_change", "变更数据或版本无效"); return }
	if err != nil { a.internalError(w, err); return }
	a.Logger.Info("接收变更", "user", id.UserID, "count", len(result.AcceptedIDs), "conflicts", result.Conflicts)
	respond(w, 200, result)
}

func (a *API) getFile(kind string) func(http.ResponseWriter, *http.Request, auth.Identity) {
	return func(w http.ResponseWriter, r *http.Request, id auth.Identity) {
		bookID := r.PathValue("bookID")
		if !a.Sync.BookExists(r.Context(), id.UserID, bookID) { fail(w, 404, "not_found", "图书不存在"); return }
		filename, digest, err := a.Files.Get(r.Context(), id.UserID, bookID, kind)
		if err != nil { fail(w, 404, "not_found", "文件尚未上传"); return }
		w.Header().Set("ETag", `"`+digest+`"`)
		if kind == "content" { w.Header().Set("Content-Type", "application/epub+zip") } else { w.Header().Set("Content-Type", "image/png") }
		http.ServeFile(w, r, filename)
	}
}

func (a *API) putFile(kind string) func(http.ResponseWriter, *http.Request, auth.Identity) {
	return func(w http.ResponseWriter, r *http.Request, id auth.Identity) {
		bookID := r.PathValue("bookID")
		if !a.Sync.BookExists(r.Context(), id.UserID, bookID) { fail(w, 404, "not_found", "图书不存在"); return }
		limit := int64(library.MaxUpload)
		if kind == "cover" { limit = library.MaxCover }
		r.Body = http.MaxBytesReader(w, r.Body, limit)
		started := time.Now()
		logger := a.Logger.With("user", id.UserID, "book", bookID, "kind", kind)
		logger.Info("开始接收文件")
		progress := &uploadProgress{reader:r.Body, logger:logger, lastReport:started}
		err := a.Files.Put(r.Context(), id.UserID, bookID, kind, progress)
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) { fail(w, 413, "too_large", "文件过大"); return }
		if errors.Is(err, library.ErrInvalid) { fail(w, 400, "invalid_file", "文件校验失败"); return }
		if err != nil { a.internalError(w, err); return }
		a.Logger.Info("文件上传完成", "user", id.UserID, "book", bookID, "kind", kind, "duration", time.Since(started))
		w.WriteHeader(204)
	}
}

func (a *API) internalError(w http.ResponseWriter, err error) {
	a.Logger.Error("请求处理失败", "error", err)
	fail(w, 500, "internal_error", "服务端处理失败")
}
