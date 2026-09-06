package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"golang.org/x/term"
	"obooks/server/internal/auth"
	"obooks/server/internal/httpapi"
	"obooks/server/internal/library"
	"obooks/server/internal/settings"
	"obooks/server/internal/storage"
	syncservice "obooks/server/internal/sync"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level:slog.LevelInfo}))
	if err := run(logger, os.Args[1:]); err != nil { logger.Error("执行失败", "error", err); os.Exit(1) }
}

func run(logger *slog.Logger, args []string) error {
	if len(args) == 0 { return errors.New("需要子命令: serve, user-create, user-reset, user-disable 或 gc") }
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	settingsFile := flags.String("settings", "", "服务端 JSON 配置文件")
	dataDirectory := flags.String("data-dir", "", "覆盖数据目录")
	username := flags.String("username", "", "管理员操作的用户名")
	allowHTTP := flags.Bool("allow-http", false, "允许非回环地址使用 HTTP, 仅用于 TLS 反向代理后方")
	retentionDays := flags.Int("retention-days", 30, "已删除文件的最短保留天数")
	if err := flags.Parse(args[1:]); err != nil { return err }
	if flags.NArg() != 0 { return errors.New("存在多余参数") }
	s, err := settings.Load(*settingsFile)
	if err != nil { return err }
	if *dataDirectory != "" { s.DataDirectory = *dataDirectory }
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	db, err := storage.Open(ctx, s.DataDirectory)
	if err != nil { return err }
	defer db.Close()
	authService := &auth.Service{DB:db, AccessTTL:time.Duration(s.AccessTokenSeconds)*time.Second, RefreshTTL:time.Duration(s.RefreshTokenSeconds)*time.Second}
	switch command {
	case "gc":
		if *retentionDays < 1 || *retentionDays > 36500 { return errors.New("保留天数必须在 1 到 36500 之间") }
		files := &library.Store{DB:db, Root:filepath.Join(s.DataDirectory, "objects")}
		count, err := files.Prune(ctx, time.Duration(*retentionDays)*24*time.Hour)
		if err == nil { logger.Info("文件回收完成", "books", count) }
		return err
	case "user-create", "user-reset", "user-disable":
		if *username == "" { return errors.New("需要 --username") }
		password := ""
		if command != "user-disable" {
			if !term.IsTerminal(int(os.Stdin.Fd())) { return errors.New("请在交互终端输入密码") }
			fmt.Fprint(os.Stderr, "密码: ")
			bytes, err := term.ReadPassword(int(os.Stdin.Fd()))
			fmt.Fprintln(os.Stderr)
			if err != nil { return err }
			password = string(bytes)
		}
		if command == "user-create" { err = authService.CreateUser(ctx, *username, password) } else { err = authService.UpdateUser(ctx, *username, password, command == "user-disable") }
		if err == nil { logger.Info("账号操作完成", "operation", command) }
		return err
	case "serve":
	default: return errors.New("未知子命令")
	}
	host, _, err := net.SplitHostPort(s.Listen)
	if err != nil { return err }
	ip := net.ParseIP(host)
	if s.TLSCertificate == "" && !*allowHTTP && (ip == nil || !ip.IsLoopback()) { return errors.New("非回环地址需要 TLS 或显式 --allow-http") }
	api := &httpapi.API{Auth:authService, Sync:&syncservice.Service{DB:db}, Files:&library.Store{DB:db, Root:filepath.Join(s.DataDirectory, "objects")}, Logger:logger}
	server := &http.Server{Addr:s.Listen, Handler:api.Handler(), ReadHeaderTimeout:10*time.Second, IdleTimeout:60*time.Second, ReadTimeout:15*time.Minute, WriteTimeout:15*time.Minute, MaxHeaderBytes:32<<10}
	done := make(chan struct{})
	go func() {
		defer close(done)
		<-ctx.Done()
		shutdownContext, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownContext); err != nil { logger.Error("服务停止失败", "error", err) }
	}()
	logger.Info("服务启动", "listen", s.Listen, "databaseVersion", 1)
	if s.TLSCertificate != "" { err = server.ListenAndServeTLS(s.TLSCertificate, s.TLSKey) } else { err = server.ListenAndServe() }
	stop()
	<-done
	if errors.Is(err, http.ErrServerClosed) { return nil }
	return err
}
