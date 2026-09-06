package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"

	"github.com/spf13/cobra"
	"golang.org/x/term"
	"obooks/server/internal/auth"
)

func newUserCreateCmd(logger *slog.Logger, opts *rootOptions) *cobra.Command {
	return newUserCmd(logger, opts, "user-create", "创建同步账号", true, func(ctx context.Context, service *auth.Service, username, password string) error {
		return service.CreateUser(ctx, username, password)
	})
}

func newUserResetCmd(logger *slog.Logger, opts *rootOptions) *cobra.Command {
	return newUserCmd(logger, opts, "user-reset", "重置账号密码并重新启用", true, func(ctx context.Context, service *auth.Service, username, password string) error {
		return service.UpdateUser(ctx, username, password, false)
	})
}

func newUserDisableCmd(logger *slog.Logger, opts *rootOptions) *cobra.Command {
	return newUserCmd(logger, opts, "user-disable", "禁用账号并撤销全部会话", false, func(ctx context.Context, service *auth.Service, username, password string) error {
		return service.UpdateUser(ctx, username, password, true)
	})
}

func newUserCmd(logger *slog.Logger, opts *rootOptions, name, short string, needPassword bool, run func(context.Context, *auth.Service, string, string) error) *cobra.Command {
	var username string
	cmd := &cobra.Command{
		Use:   name,
		Short: short,
		Args:  cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			return runUser(logger, opts, name, username, needPassword, run)
		},
	}
	cmd.Flags().StringVarP(&username, "username", "u", "", "管理员操作的用户名")
	_ = cmd.MarkFlagRequired("username")
	return cmd
}

func runUser(logger *slog.Logger, opts *rootOptions, operation, username string, needPassword bool, run func(context.Context, *auth.Service, string, string) error) error {
	ctx, stop := signalContext()
	defer stop()
	s, db, err := opts.open(ctx)
	if err != nil {
		return err
	}
	defer db.Close()
	password := ""
	if needPassword {
		password, err = readPassword()
		if err != nil {
			return err
		}
	}
	err = run(ctx, newAuthService(s, db), username, password)
	if err == nil {
		logger.Info("账号操作完成", "operation", operation)
	}
	return err
}

func readPassword() (string, error) {
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return "", errors.New("请在交互终端输入密码")
	}
	fmt.Fprint(os.Stderr, "密码: ")
	bytes, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Fprintln(os.Stderr)
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}
