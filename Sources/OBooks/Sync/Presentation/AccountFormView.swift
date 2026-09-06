import SwiftUI

/// 添加或编辑同步账号的独立窗口.
struct AccountFormView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var sync: SyncCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var deviceName = Host.current().localizedName ?? "Mac"
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var busy = false

    init(appModel: AppModel) {
        _appModel = ObservedObject(wrappedValue: appModel)
        _sync = ObservedObject(wrappedValue: appModel.sync)
    }

    private var kind: AccountFormKind { appModel.accountForm ?? .add }
    private var isAdd: Bool { kind == .add }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isAdd ? "添加账号" : "编辑账号")
                .font(.title2.weight(.semibold))
            Text(isAdd ? "先验证登录, 成功后才会保存到本机账号列表." : "可更新设备名称, 也可修改云端密码. 改密后其他设备需要重新登录.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                if isAdd {
                    TextField("服务地址", text: $server, prompt: Text("https://books.example.com"))
                        .disabled(busy)
                    TextField("用户名", text: $username)
                        .disabled(busy)
                    TextField("设备名称", text: $deviceName)
                        .disabled(busy)
                    SecureField("密码", text: $password)
                        .disabled(busy)
                } else {
                    LabeledContent("服务地址", value: sync.account?.server.absoluteString ?? "")
                    LabeledContent("用户名", value: sync.account?.username ?? "")
                    TextField("设备名称", text: $deviceName)
                        .disabled(busy)
                    SecureField("当前密码", text: $currentPassword)
                        .disabled(busy)
                    SecureField("新密码", text: $newPassword)
                        .disabled(busy)
                    SecureField("确认新密码", text: $confirmPassword)
                        .disabled(busy)
                }
            }
            if let error = appModel.accountActionError ?? passwordError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("取消", action: close)
                    .disabled(busy)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(isAdd ? "登录并保存" : "保存") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || !canSubmit)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear(perform: fill)
        .onChange(of: appModel.accountForm) { _, _ in fill() }
    }

    private var passwordError: String? {
        guard !isAdd, wantsPasswordChange else { return nil }
        if newPassword != confirmPassword { return "两次输入的新密码不一致" }
        if newPassword.utf8.count < 12 { return "新密码长度必须不少于 12 字节" }
        return nil
    }

    private var wantsPasswordChange: Bool {
        !currentPassword.isEmpty || !newPassword.isEmpty || !confirmPassword.isEmpty
    }

    private var canSubmit: Bool {
        if isAdd {
            return !server.isEmpty && !username.isEmpty && !password.isEmpty && !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if passwordError != nil { return false }
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return false }
        if wantsPasswordChange {
            return !currentPassword.isEmpty && !newPassword.isEmpty && !confirmPassword.isEmpty
        }
        return name != (sync.deviceName)
    }

    private func fill() {
        if isAdd {
            server = ""
            username = ""
            password = ""
            deviceName = Host.current().localizedName ?? "Mac"
        } else {
            server = sync.account?.server.absoluteString ?? ""
            username = sync.account?.username ?? ""
            deviceName = sync.deviceName
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
        }
    }

    private func close() {
        appModel.closeAccountForm()
        dismiss()
    }

    private func submit() async {
        busy = true
        defer { busy = false }
        if isAdd {
            let signedIn = await appModel.loginToAccount(
                server: server,
                username: username,
                password: password,
                deviceName: deviceName
            )
            if signedIn { close() }
            return
        }
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = await appModel.updateAccount(
            deviceName: name == sync.deviceName ? nil : name,
            currentPassword: wantsPasswordChange ? currentPassword : nil,
            newPassword: wantsPasswordChange ? newPassword : nil
        )
        if saved { close() }
    }
}
