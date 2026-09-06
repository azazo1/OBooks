import SwiftUI

struct SyncSettingsView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var sync: SyncCoordinator
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var addingAccount = false
    @State private var newDeviceName = Host.current().localizedName ?? "Mac"

    init(appModel: AppModel) {
        _appModel = ObservedObject(wrappedValue: appModel)
        _sync = ObservedObject(wrappedValue: appModel.sync)
    }

    private var busy: Bool { sync.isSyncing || !sync.downloading.isEmpty }
    private var bound: Bool { sync.account != nil && !addingAccount }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "icloud").font(.title2)
                    Text("云同步").font(.title2.weight(.semibold))
                    Spacer()
                }
                if appModel.workspace != nil, !appModel.profiles.isEmpty {
                    AccountSwitcherSection(
                        profiles: appModel.profiles,
                        activeID: appModel.workspace?.activeID,
                        busy: busy,
                        hasSavedSession: appModel.hasSavedSession(for:),
                        onSwitch: switchToProfile,
                        onAdd: beginAddingAccount,
                        addingAccount: addingAccount
                    )
                }
                if addingAccount {
                    addAccountForm
                } else {
                    currentAccountForm
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
                    if let error = sync.lastError { Text(error).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                }
                .font(.callout)
                actionRow
                if !appModel.localCopySources.isEmpty {
                    LocalLibraryCopySection(
                        sources: appModel.localCopySources,
                        isBusy: busy || appModel.copyStatus != nil,
                        status: appModel.copyStatus
                    ) { profile in
                        appModel.copyFromLocalProfile(profile)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .frame(minWidth: 500, idealWidth: 520, maxHeight: 680)
        .onAppear { fillFromAccount() }
        .onChange(of: appModel.workspace?.activeID ?? "") { _, _ in
            if !addingAccount { fillFromAccount() }
        }
    }

    private var currentAccountForm: some View {
        Form {
            TextField("服务地址", text: $server, prompt: Text("https://books.example.com"))
                .disabled(bound || busy)
            TextField("用户名", text: $username)
                .disabled(bound || busy)
            TextField("设备名称", text: $sync.deviceName)
                .disabled(sync.isSignedIn || busy)
            if !sync.isSignedIn {
                SecureField("密码", text: $password)
            }
        }
    }

    private var addAccountForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("登录新账号不会退出当前账号.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                TextField("服务地址", text: $server, prompt: Text("https://books.example.com"))
                    .disabled(busy)
                TextField("用户名", text: $username)
                    .disabled(busy)
                TextField("设备名称", text: $newDeviceName)
                    .disabled(busy)
                SecureField("密码", text: $password)
                    .disabled(busy)
            }
            HStack {
                Button("取消") {
                    addingAccount = false
                    password = ""
                    fillFromAccount()
                }
                .disabled(busy)
                Spacer()
                Button("登录新账号") {
                    submitLogin(deviceName: newDeviceName)
                }
                .buttonStyle(.borderedProminent)
                .disabled(server.isEmpty || username.isEmpty || password.isEmpty || busy)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            if sync.isSignedIn {
                Button { Task { await sync.synchronize() } } label: { Label("立即同步", systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(busy)
                Button { Task { await sync.downloadAll() } } label: { Label("下载全部", systemImage: "icloud.and.arrow.down") }
                    .disabled(busy)
                Spacer()
                Button("退出登录") {
                    Task {
                        await sync.logout()
                        if !addingAccount { fillFromAccount() }
                    }
                }
                .disabled(busy)
            } else if !addingAccount {
                Spacer()
                Button("登录") {
                    submitLogin(deviceName: nil)
                }
                .buttonStyle(.borderedProminent)
                .disabled(server.isEmpty || username.isEmpty || password.isEmpty || busy)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func beginAddingAccount() {
        addingAccount = true
        server = ""
        username = ""
        password = ""
        newDeviceName = Host.current().localizedName ?? "Mac"
    }

    private func switchToProfile(_ profile: LibraryProfile) {
        addingAccount = false
        password = ""
        appModel.switchToProfile(profile.id)
        fillFromAccount()
    }

    private func submitLogin(deviceName: String?) {
        let secret = password
        password = ""
        Task {
            let signedIn = await appModel.loginToAccount(
                server: server,
                username: username,
                password: secret,
                deviceName: deviceName
            )
            if signedIn {
                addingAccount = false
                fillFromAccount()
            }
        }
    }

    private func fillFromAccount() {
        guard !addingAccount else { return }
        server = sync.account?.server.absoluteString ?? ""
        username = sync.account?.username ?? ""
    }
}
