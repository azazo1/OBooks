package main

import (
	"errors"
	"log/slog"
	"path/filepath"
	"time"

	"github.com/spf13/cobra"
	"obooks/server/internal/library"
)

func newGCCmd(logger *slog.Logger, opts *rootOptions) *cobra.Command {
	retentionDays := 30
	cmd := &cobra.Command{
		Use:   "gc",
		Short: "回收已删除书籍的服务器文件",
		Args:  cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			return runGC(logger, opts, retentionDays)
		},
	}
	cmd.Flags().IntVar(&retentionDays, "retention-days", 30, "已删除文件的最短保留天数")
	return cmd
}

func runGC(logger *slog.Logger, opts *rootOptions, retentionDays int) error {
	if retentionDays < 1 || retentionDays > 36500 {
		return errors.New("保留天数必须在 1 到 36500 之间")
	}
	ctx, stop := signalContext()
	defer stop()
	s, db, err := opts.open(ctx)
	if err != nil {
		return err
	}
	defer db.Close()
	files := &library.Store{DB: db, Root: filepath.Join(s.DataDirectory, "objects")}
	count, err := files.Prune(ctx, time.Duration(retentionDays)*24*time.Hour)
	if err == nil {
		logger.Info("文件回收完成", "books", count)
	}
	return err
}
