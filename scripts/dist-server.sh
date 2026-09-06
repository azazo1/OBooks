#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
# shellcheck source=scripts/display-version.sh
source "$project_root/scripts/display-version.sh"

host_os="$(go env GOHOSTOS)"
host_arch="$(go env GOHOSTARCH)"
goos="${GOOS:-$host_os}"
goarch="${GOARCH:-$host_arch}"

case "$goos" in
    darwin)
        default_platform="macos"
        ;;
    linux)
        default_platform="linux"
        ;;
    windows)
        default_platform="windows"
        ;;
    *)
        echo "不支持的 GOOS: $goos" >&2
        exit 1
        ;;
esac

case "$goarch" in
    amd64)
        default_arch="x86_64"
        expected_unix_arch="x86-64|x86_64"
        expected_windows_arch="x86-64|x86_64"
        ;;
    arm64)
        default_arch="aarch64"
        expected_unix_arch="arm64|aarch64"
        expected_windows_arch="ARM|Aarch64|aarch64|arm64"
        ;;
    *)
        echo "不支持的 GOARCH: $goarch" >&2
        exit 1
        ;;
esac

platform="${PLATFORM:-$default_platform}"
arch="${ARCH:-$default_arch}"
if [[ "$platform" != "$default_platform" || "$arch" != "$default_arch" ]]; then
    echo "PLATFORM/ARCH 与 GOOS/GOARCH 不一致: $platform/$arch vs $goos/$goarch" >&2
    exit 1
fi

version="${VERSION:-$(compute_build_version)}"
display_version="$(compute_display_version)"
if [[ -z "$version" || "$version" == */* || -z "$display_version" ]]; then
    echo "无效的构建版本: $version / $display_version" >&2
    exit 1
fi

binary_name="obooks-server"
ext="tar.gz"
if [[ "$goos" == "windows" ]]; then
    binary_name="obooks-server.exe"
    ext="zip"
fi

dist_dir="${DIST_DIR:-$project_root/dist}"
mkdir -p "$dist_dir"
archive="$dist_dir/obooks-server-${version}-${platform}-${arch}.${ext}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
binary="$work/$binary_name"
rm -f "$archive"

echo "开始构建 obooks-server $display_version ($platform/$arch, $goos/$goarch)"
go version
CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" go build \
    -C server \
    -trimpath \
    -ldflags "-X main.version=$display_version" \
    -o "$binary" \
    ./cmd/obooks-server

if [[ ! -f "$binary" ]]; then
    echo "缺少可执行文件: $binary" >&2
    exit 1
fi
if [[ "$goos" != "windows" && ! -x "$binary" ]]; then
    echo "缺少可执行权限: $binary" >&2
    exit 1
fi

binary_format="$(file -b "$binary")"
echo "文件格式: $binary_format"
case "$goos" in
    linux)
        if [[ "$binary_format" != *ELF* ]] || ! grep -Eqi "$expected_unix_arch" <<<"$binary_format"; then
            echo "可执行文件格式或架构不正确: $binary_format" >&2
            exit 1
        fi
        ;;
    darwin)
        if [[ "$binary_format" != *Mach-O* ]] || ! grep -Eqi "$expected_unix_arch" <<<"$binary_format"; then
            echo "可执行文件格式或架构不正确: $binary_format" >&2
            exit 1
        fi
        ;;
    windows)
        if [[ "$binary_format" != *PE32* ]] || ! grep -Eqi "$expected_windows_arch" <<<"$binary_format"; then
            echo "可执行文件格式或架构不正确: $binary_format" >&2
            exit 1
        fi
        ;;
esac

if [[ "$goos" == "$host_os" && "$goarch" == "$host_arch" ]]; then
    got="$("$binary" --version)"
    if [[ "$got" != "$display_version" ]]; then
        echo "版本输出不正确: $got (期望 $display_version)" >&2
        exit 1
    fi
    echo "版本检查通过: $got"
fi

if [[ "$ext" == "zip" ]]; then
    python3 - "$archive" "$binary" "$binary_name" <<'PY'
import sys
import zipfile

archive, binary, name = sys.argv[1], sys.argv[2], sys.argv[3]
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zipped:
    zipped.write(binary, name)
PY
else
    tar -C "$work" -czf "$archive" "$binary_name"
fi

if [[ ! -s "$archive" ]]; then
    echo "归档生成失败: $archive" >&2
    exit 1
fi

echo "已生成 $archive"
