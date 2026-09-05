#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "dist-macos.sh 只能在 macOS 上运行" >&2
    exit 1
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

machine="$(uname -m)"
case "$machine" in
    arm64)
        default_arch="aarch64"
        ;;
    x86_64)
        default_arch="x86_64"
        ;;
    *)
        echo "不支持的 macOS 架构: $machine" >&2
        exit 1
        ;;
esac

arch="${ARCH:-$default_arch}"
swift_triple="${SWIFT_TRIPLE:-${machine}-apple-macosx14.0}"
case "$arch" in
    aarch64)
        expected_file_arch="arm64"
        ;;
    x86_64)
        expected_file_arch="x86_64"
        ;;
    *)
        echo "不支持的发布架构: $arch" >&2
        exit 1
        ;;
esac

if [[ -n "${VERSION:-}" ]]; then
    version="$VERSION"
else
    exact_tag="$(git describe --tags --match 'v[0-9]*' --exact-match 2>/dev/null || true)"
    if [[ -n "$exact_tag" ]]; then
        version="${exact_tag#v}"
    else
        last_tag="$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || true)"
        short_sha="$(git rev-parse --short=7 HEAD)"
        if [[ -n "$last_tag" ]]; then
            version="${last_tag#v}-$short_sha"
        else
            version="0.0.0-$short_sha"
        fi
    fi
fi

if [[ -z "$version" || "$version" == */* ]]; then
    echo "无效的构建版本: $version" >&2
    exit 1
fi

echo "开始构建 OBooks $version ($arch, $swift_triple)"
swift build --configuration release --product OBooks --triple "$swift_triple"

bin_path="$(swift build --configuration release --product OBooks --triple "$swift_triple" --show-bin-path)"
binary="$bin_path/OBooks"
if [[ ! -x "$binary" ]]; then
    echo "缺少可执行文件: $binary" >&2
    exit 1
fi

binary_format="$(file "$binary")"
if [[ "$binary_format" != *"Mach-O"* || "$binary_format" != *"$expected_file_arch"* ]]; then
    echo "可执行文件格式或架构不正确: $binary_format" >&2
    exit 1
fi

dist_dir="${DIST_DIR:-$project_root/dist}"
mkdir -p "$dist_dir"
app_bundle="$dist_dir/OBooks.app"
archive="$dist_dir/OBooks-${version}-macos-${arch}.dmg"
icon_file="$project_root/assets/obooks-icon.icns"
rm -rf "$app_bundle"
rm -f "$archive"
if [[ ! -s "$icon_file" ]]; then
    echo "缺少 macOS 应用图标: $icon_file" >&2
    exit 1
fi

mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$binary" "$app_bundle/Contents/MacOS/OBooks"
cp "$icon_file" "$app_bundle/Contents/Resources/AppIcon.icns"

build_number="$(git rev-list --count HEAD)"
printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0">' \
    '<dict>' \
    '    <key>CFBundleDisplayName</key>' \
    '    <string>OBooks</string>' \
    '    <key>CFBundleExecutable</key>' \
    '    <string>OBooks</string>' \
    '    <key>CFBundleIconFile</key>' \
    '    <string>AppIcon</string>' \
    '    <key>CFBundleIdentifier</key>' \
    '    <string>com.azazo1.obooks</string>' \
    '    <key>CFBundleName</key>' \
    '    <string>OBooks</string>' \
    '    <key>CFBundlePackageType</key>' \
    '    <string>APPL</string>' \
    '    <key>CFBundleShortVersionString</key>' \
    "    <string>$version</string>" \
    '    <key>CFBundleVersion</key>' \
    "    <string>$build_number</string>" \
    '    <key>LSMinimumSystemVersion</key>' \
    '    <string>14.0</string>' \
    '    <key>NSHighResolutionCapable</key>' \
    '    <true/>' \
    '</dict>' \
    '</plist>' > "$app_bundle/Contents/Info.plist"

chmod +x "$app_bundle/Contents/MacOS/OBooks"
hdiutil create \
    -volname "OBooks $version" \
    -srcfolder "$app_bundle" \
    -ov \
    -format UDZO \
    "$archive" >/dev/null

if [[ ! -s "$archive" ]]; then
    echo "DMG 生成失败: $archive" >&2
    exit 1
fi

rm -rf "$app_bundle"
echo "已生成 $archive"
