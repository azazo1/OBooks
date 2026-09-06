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

server_ldflags := "-X main.version=" + trim(`./scripts/display-version.sh`)

# 根据当前平台生成发布产物.
[macos]
dist:
    ./scripts/dist-macos.sh
    ./scripts/dist-server.sh

# 根据当前平台生成发布产物.
[linux]
dist:
    ./scripts/dist-server.sh

# 根据当前平台生成发布产物.
[windows]
dist:
    powershell -NoProfile -File scripts/dist-server.ps1

# 构建 Go 同步服务端.
server-build:
    cd server && go build -ldflags "{{server_ldflags}}" ./cmd/obooks-server

# 测试 Go 同步服务端.
server-test:
    cd server && go test ./...

# just server-run --settings settings.example.json
# 启动 Go 同步服务端.
server-run *args:
    cd server && go run -ldflags "{{server_ldflags}}" ./cmd/obooks-server serve {{args}}

# just server-admin user-create --username reader
# 管理同步服务账号.
server-admin +args:
    cd server && go run -ldflags "{{server_ldflags}}" ./cmd/obooks-server {{args}}

# 使用临时服务验证两个 Swift 客户端的完整同步流程.
sync-integration:
    swift test --filter SyncTransportTests
    cd server && OBOOKS_RUN_SWIFT_INTEGRATION=1 go test -count=1 -v ./internal/httpapi -run TestSwiftClientIntegration
