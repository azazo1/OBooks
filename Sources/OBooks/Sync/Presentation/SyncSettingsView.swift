import SwiftUI

struct SyncSettingsView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var sync: SyncCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    init(appModel: AppModel) {
        _appModel = ObservedObject(wrappedValue: appModel)
        _sync = ObservedObject(wrappedValue: appModel.sync)
    }

    private var busy: Bool { sync.isSyncing || !sync.downloading.isEmpty }
    private var bound: Bool { sync.account != nil }
    private var editAction: (() -> Void)? {
        sync.isSignedIn ? { [self] in openForm(.edit) } : nil
    }
    private var selectedProfileID: Binding<String> {
        Binding(
            get: { appModel.workspace?.activeID ?? "" },
            set: { newID in
                guard let profile = appModel.profiles.first(where: { $0.id == newID }) else { return }
                switchToProfile(profile)
            }
        )
    }

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
                        selectedID: selectedProfileID,
                        busy: busy,
                        hasSavedSession: appModel.hasSavedSession(for:),
                        onAdd: { openForm(.add) },
                        onEdit: editAction
                    )
                }
                currentAccountForm
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
                    if let error = appModel.accountActionError ?? sync.lastError { Text(error).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
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
            fillFromAccount()
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
                        fillFromAccount()
                    }
                }
                .disabled(busy)
            } else {
                Spacer()
                Button("登录") {
                    submitLogin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(server.isEmpty || username.isEmpty || password.isEmpty || busy)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func openForm(_ kind: AccountFormKind) {
        appModel.openAccountForm(kind)
        openWindow(id: "account-form")
    }

    private func switchToProfile(_ profile: LibraryProfile) {
        password = ""
        appModel.switchToProfile(profile.id)
        fillFromAccount()
    }

    private func submitLogin() {
        let secret = password
        password = ""
        Task {
            let signedIn = await appModel.loginToAccount(
                server: server,
                username: username,
                password: secret,
                deviceName: sync.deviceName
            )
            if signedIn { fillFromAccount() }
        }
    }

    private func fillFromAccount() {
        server = sync.account?.server.absoluteString ?? ""
        username = sync.account?.username ?? ""
    }
}
