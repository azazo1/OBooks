package main

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"path/filepath"
	"time"

	"github.com/spf13/cobra"
	"obooks/server/internal/httpapi"
	"obooks/server/internal/library"
	syncservice "obooks/server/internal/sync"
)

func newServeCmd(logger *slog.Logger, opts *rootOptions) *cobra.Command {
	var allowHTTP bool
	cmd := &cobra.Command{
		Use:   "serve",
		Short: "启动云同步服务",
		Args:  cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			return runServe(logger, opts, allowHTTP)
		},
	}
	cmd.Flags().BoolVar(&allowHTTP, "allow-http", false, "允许非回环地址使用 HTTP, 仅用于 TLS 反向代理后方")
	return cmd
}

func runServe(logger *slog.Logger, opts *rootOptions, allowHTTP bool) error {
	ctx, stop := signalContext()
	defer stop()
	s, db, err := opts.open(ctx)
	if err != nil {
		return err
	}
	defer db.Close()
	host, _, err := net.SplitHostPort(s.Listen)
	if err != nil {
		return err
	}
	ip := net.ParseIP(host)
	if s.TLSCertificate == "" && !allowHTTP && (ip == nil || !ip.IsLoopback()) {
		return errors.New("非回环地址需要 TLS 或显式 --allow-http")
	}
	api := &httpapi.API{
		Auth:   newAuthService(s, db),
		Sync:   &syncservice.Service{DB: db},
		Files:  &library.Store{DB: db, Root: filepath.Join(s.DataDirectory, "objects")},
		Logger: logger,
	}
	server := &http.Server{
		Addr:              s.Listen,
		Handler:           api.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       60 * time.Second,
		ReadTimeout:       15 * time.Minute,
		WriteTimeout:      15 * time.Minute,
		MaxHeaderBytes:    32 << 10,
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		<-ctx.Done()
		shutdownContext, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownContext); err != nil {
			logger.Error("服务停止失败", "error", err)
		}
	}()
	logger.Info("服务启动", "listen", s.Listen, "databaseVersion", 1)
	if s.TLSCertificate != "" {
		err = server.ListenAndServeTLS(s.TLSCertificate, s.TLSKey)
	} else {
		err = server.ListenAndServe()
	}
	stop()
	<-done
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
