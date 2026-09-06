import SwiftUI

struct SyncSettingsView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var sync: SyncCoordinator
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var switchingAccount = false

    init(appModel: AppModel) {
        _appModel = ObservedObject(wrappedValue: appModel)
        _sync = ObservedObject(wrappedValue: appModel.sync)
    }

    private var bound: Bool { sync.account != nil && !switchingAccount }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "icloud").font(.title2)
                Text("云同步").font(.title2.weight(.semibold))
                Spacer()
            }
            Form {
                TextField("服务地址", text: $server, prompt: Text("https://books.example.com"))
                    .disabled(bound || sync.isSyncing)
                TextField("用户名", text: $username)
                    .disabled(bound || sync.isSyncing)
                TextField("设备名称", text: $sync.deviceName)
                    .disabled(sync.isSignedIn || sync.isSyncing)
                if !sync.isSignedIn {
                    SecureField("密码", text: $password)
                }
            }
            if let profile = appModel.workspace?.activeProfile {
                Text(profile.isUnbound ? "当前是未绑定书库, 登录其他账号会新建空书库, 不会带走这里的书." : "当前书库: " + profile.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(sync.status, systemImage: sync.lastError == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.icloud")
                if let progress = sync.transferProgress { ProgressView(value: progress).frame(height: 8) }
                if sync.isSyncing { ProgressView().controlSize(.small) }
                if sync.pendingCount > 0 { Text("待同步: \(sync.pendingCount)").foregroundStyle(.secondary) }
                if let date = sync.lastSyncedAt { Text("最近同步: " + date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
                if let status = appModel.copyStatus { Text(status).foregroundStyle(.secondary) }
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
                    Button("切换账号") {
                        switchingAccount = true
                        server = ""
                        username = ""
                        Task { await sync.logout() }
                    }
                    .disabled(sync.isSyncing)
                } else {
                    if switchingAccount {
                        Button("取消") {
                            switchingAccount = false
                            fillFromAccount()
                        }
                    } else if sync.account != nil {
                        Button("切换账号") {
                            switchingAccount = true
                            server = ""
                            username = ""
                        }
                    }
                    Spacer()
                    Button(switchingAccount ? "登录新账号" : "登录") {
                        let secret = password
                        password = ""
                        Task {
                            await appModel.loginToAccount(server: server, username: username, password: secret)
                            if sync.isSignedIn { switchingAccount = false }
                            fillFromAccount()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(server.isEmpty || username.isEmpty || password.isEmpty || sync.isSyncing)
                    .keyboardShortcut(.defaultAction)
                }
            }
            if !appModel.localCopySources.isEmpty {
                Divider()
                Text("从本地书库复制")
                    .font(.headline)
                Text("复制到当前书库, 按书合并书签和高亮, 不删除来源.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(appModel.localCopySources) { profile in
                    Button("复制 " + profile.title) {
                        appModel.copyFromLocalProfile(profile)
                    }
                    .disabled(sync.isSyncing || appModel.copyStatus != nil)
                }
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear { fillFromAccount() }
    }

    private func fillFromAccount() {
        guard !switchingAccount else { return }
        server = sync.account?.server.absoluteString ?? ""
        username = sync.account?.username ?? ""
    }
}
