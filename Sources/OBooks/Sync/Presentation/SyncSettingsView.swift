import SwiftUI

struct SyncSettingsView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var sync: SyncCoordinator
    @State private var password = ""
    @State private var confirmingDelete = false

    init(appModel: AppModel) {
        _appModel = ObservedObject(wrappedValue: appModel)
        _sync = ObservedObject(wrappedValue: appModel.sync)
    }

    private var busy: Bool { sync.isSyncing || !sync.downloading.isEmpty }
    private var settingsError: String? {
        if appModel.accountForm != nil { return sync.lastError }
        return appModel.accountActionError ?? sync.lastError
    }
    private var bound: Bool { sync.account != nil }
    private var editAction: (() -> Void)? {
        sync.isSignedIn ? { [self] in openForm(.edit) } : nil
    }
    private var removableProfile: LibraryProfile? {
        appModel.workspace?.activeProfile.flatMap { $0.isUnbound ? nil : $0 }
    }
    private var removeAction: (() -> Void)? {
        removableProfile == nil ? nil : { confirmingDelete = true }
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
                        onEdit: editAction,
                        onRemove: removeAction
                    )
                }
                if let profile = appModel.workspace?.activeProfile, profile.isUnbound {
                    Text("当前是未绑定书库, 用添加账号登录云端, 不会带走这里的书.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if bound, !sync.isSignedIn {
                    Form {
                        SecureField("密码", text: $password)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label(sync.status, systemImage: sync.lastError == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.icloud")
                    if let progress = sync.transferProgress { ProgressView(value: progress).frame(height: 8) }
                    if sync.isSyncing { ProgressView().controlSize(.small) }
                    if sync.pendingCount > 0 { Text("待同步: \(sync.pendingCount)").foregroundStyle(.secondary) }
                    if let date = sync.lastSyncedAt { Text("最近同步: " + date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
                    if let error = settingsError { Text(error).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
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
            .frame(width: 520, alignment: .leading)
            .animation(.easeInOut(duration: 0.22), value: sync.isSignedIn)
            .animation(.easeInOut(duration: 0.22), value: bound)
            .animation(.easeInOut(duration: 0.22), value: settingsError)
            .animation(.easeInOut(duration: 0.22), value: appModel.localCopySources.count)
            .tracksWindowContentHeight()
            .background(SettingsWindowProbe())
        .sheet(isPresented: accountFormPresented) {
            AccountFormView(appModel: appModel)
        }
        .confirmationDialog(
            "删除本机账号",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("删除本机账号", role: .destructive) {
                guard let profile = removableProfile else { return }
                Task {
                    await appModel.removeLocalAccount(profile)
                    password = ""
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将从这台电脑删除 " + (removableProfile?.title ?? "该账号") + " 的书库和登录状态, 云端账号不会删除.")
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
                        password = ""
                    }
                }
                .disabled(busy)
            } else if bound {
                Spacer()
                Button("登录") {
                    submitLogin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || busy)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var accountFormPresented: Binding<Bool> {
        Binding(
            get: { appModel.accountForm != nil },
            set: { presented in
                if !presented { appModel.closeAccountForm() }
            }
        )
    }

    private func openForm(_ kind: AccountFormKind) {
        appModel.openAccountForm(kind)
    }

    private func switchToProfile(_ profile: LibraryProfile) {
        password = ""
        appModel.switchToProfile(profile.id)
    }

    private func submitLogin() {
        guard let account = sync.account else { return }
        let secret = password
        password = ""
        Task {
            _ = await appModel.loginToAccount(
                server: account.server.absoluteString,
                username: account.username,
                password: secret
            )
        }
    }
}
