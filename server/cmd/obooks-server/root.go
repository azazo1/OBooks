package main

import (
	"context"
	"database/sql"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/spf13/cobra"
	"obooks/server/internal/auth"
	"obooks/server/internal/settings"
	"obooks/server/internal/storage"
)

// version 由构建脚本根据 git 状态通过 ldflags 注入.
var version string

type rootOptions struct {
	settingsFile  string
	dataDirectory string
}

func newRoot(logger *slog.Logger) *cobra.Command {
	opts := &rootOptions{}
	cmd := &cobra.Command{
		Use:           "obooks-server",
		Short:         "OBooks 云同步服务",
		Version:       version,
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	cmd.SetVersionTemplate("{{.Version}}\n")
	cmd.CompletionOptions.DisableDefaultCmd = true
	flags := cmd.PersistentFlags()
	flags.StringVarP(&opts.settingsFile, "settings", "s", "", "服务端 JSON 配置文件")
	flags.StringVar(&opts.dataDirectory, "data-dir", "", "覆盖数据目录")
	cmd.AddCommand(
		newServeCmd(logger, opts),
		newUserCreateCmd(logger, opts),
		newUserResetCmd(logger, opts),
		newUserDisableCmd(logger, opts),
		newGCCmd(logger, opts),
	)
	for _, child := range cmd.Commands() {
		child.SilenceUsage = true
		child.SilenceErrors = true
	}
	return cmd
}

func execute(logger *slog.Logger, args []string) error {
	cmd := newRoot(logger)
	cmd.SetArgs(args)
	return cmd.Execute()
}

func signalContext() (context.Context, context.CancelFunc) {
	return signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
}

func (o *rootOptions) open(ctx context.Context) (settings.Settings, *sql.DB, error) {
	s, err := settings.Load(o.settingsFile)
	if err != nil {
		return s, nil, err
	}
	if o.dataDirectory != "" {
		s.DataDirectory = o.dataDirectory
	}
	db, err := storage.Open(ctx, s.DataDirectory)
	return s, db, err
}

func newAuthService(s settings.Settings, db *sql.DB) *auth.Service {
	return &auth.Service{
		DB:         db,
		AccessTTL:  time.Duration(s.AccessTokenSeconds) * time.Second,
		RefreshTTL: time.Duration(s.RefreshTokenSeconds) * time.Second,
	}
}
