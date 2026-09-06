#!/usr/bin/env bash
# 根据 git 状态生成版本号.
# 展示版本:
# - 干净且恰好落在版本 tag 上: 直接显示该 tag, 如 v1.2.3.
# - 干净但处于非 tag commit: 最近 tag 后加 "-" 和 7 位短 hash, 如 v1.2.3-a1b2c3d.
# - HEAD 工作区有未提交改动: 改用 "^" 分隔, 如 v1.2.3^a1b2c3d.
# 基础版本样式跟随最近一个版本 tag.
# 产物文件名使用 compute_build_version, 去掉 tag 的可选 v 前缀, 且不含脏工作区标记.

compute_display_version() {
    local dirty=false
    # 用 porcelain 同时覆盖已跟踪文件的修改, 暂存区改动和未跟踪文件.
    if [[ -n "$(git status --porcelain)" ]]; then
        dirty=true
    fi
    local exact_tag last_tag short_sha
    exact_tag="$(git describe --tags --match 'v[0-9]*' --exact-match 2>/dev/null || true)"
    short_sha="$(git rev-parse --short=7 HEAD)"
    if [[ -n "$exact_tag" ]]; then
        if [[ "$dirty" == true ]]; then
            printf '%s^%s\n' "$exact_tag" "$short_sha"
        else
            printf '%s\n' "$exact_tag"
        fi
        return
    fi
    last_tag="$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || true)"
    if [[ -n "$last_tag" ]]; then
        if [[ "$dirty" == true ]]; then
            printf '%s^%s\n' "$last_tag" "$short_sha"
        else
            printf '%s-%s\n' "$last_tag" "$short_sha"
        fi
    else
        if [[ "$dirty" == true ]]; then
            printf 'v0.0.0^%s\n' "$short_sha"
        else
            printf 'v0.0.0-%s\n' "$short_sha"
        fi
    fi
}

compute_build_version() {
    local exact_tag last_tag short_sha
    exact_tag="$(git describe --tags --match 'v[0-9]*' --exact-match 2>/dev/null || true)"
    if [[ -n "$exact_tag" ]]; then
        printf '%s\n' "${exact_tag#v}"
        return
    fi
    last_tag="$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || true)"
    short_sha="$(git rev-parse --short=7 HEAD)"
    if [[ -n "$last_tag" ]]; then
        printf '%s-%s\n' "${last_tag#v}" "$short_sha"
    else
        printf '0.0.0-%s\n' "$short_sha"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
    case "${1:-}" in
        --build)
            compute_build_version
            ;;
        "")
            compute_display_version
            ;;
        *)
            echo "未知参数: $1" >&2
            exit 1
            ;;
    esac
fi
