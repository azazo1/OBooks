package main

import (
	"log/slog"
	"os"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))
	if err := execute(logger, os.Args[1:]); err != nil {
		logger.Error("执行失败", "error", err)
		os.Exit(1)
	}
}
