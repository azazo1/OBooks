# just
# 显示所有可用命令.
default:
    @just --list

# just build
# 构建 macOS 初版应用.
build:
    swift build

# just test
# 运行测试.
test:
    swift test

# just run
# 启动 macOS 初版应用.
run:
    swift run OBooks

# just clean
# 清理 SwiftPM 构建产物.
clean:
    swift package clean

# just dist
# 根据当前平台生成 macOS 发布产物.
[macos]
dist:
    ./scripts/dist-macos.sh
