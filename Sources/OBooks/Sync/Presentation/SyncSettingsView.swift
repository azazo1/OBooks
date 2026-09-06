import SwiftUI

struct SyncSettingsView: View {
    @ObservedObject var sync: SyncCoordinator
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "icloud").font(.title2)
                Text("云同步").font(.title2.weight(.semibold))
                Spacer()
            }
            Form {
                TextField("服务地址", text: $server, prompt: Text("https://books.example.com"))
                    .disabled(sync.isSignedIn || sync.isSyncing)
                TextField("用户名", text: $username)
                    .disabled(sync.isSignedIn || sync.isSyncing)
                TextField("设备名称", text: $sync.deviceName)
                    .disabled(sync.isSignedIn || sync.isSyncing)
                if !sync.isSignedIn {
                    SecureField("密码", text: $password)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(sync.status, systemImage: sync.lastError == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.icloud")
                if let progress = sync.transferProgress { ProgressView(value: progress).frame(height: 8) }
                if sync.isSyncing { ProgressView().controlSize(.small) }
                if sync.pendingCount > 0 { Text("待同步: \(sync.pendingCount)").foregroundStyle(.secondary) }
                if let date = sync.lastSyncedAt { Text("最近同步: " + date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
                if let error = sync.lastError { Text(error).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            }
            .font(.callout)
            HStack {
                if sync.isSignedIn {
                    Button { Task { await sync.synchronize() } } label: { Label("立即同步", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(sync.isSyncing || !sync.downloading.isEmpty)
                    Button { Task { await sync.downloadAll() } } label: { Label("下载全部", systemImage: "icloud.and.arrow.down") }
                        .disabled(sync.isSyncing || !sync.downloading.isEmpty)
                    Spacer()
                    Button("退出登录") { Task { await sync.logout() } }
                } else {
                    Spacer()
                    Button("登录") {
                        let secret = password
                        password = ""
                        Task { await sync.login(server: server, username: username, password: secret) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(server.isEmpty || username.isEmpty || password.isEmpty || sync.isSyncing)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            server = sync.account?.server.absoluteString ?? ""
            username = sync.account?.username ?? ""
        }
    }
}
