import SwiftUI

/// 设置页中的已保存账号下拉框, 切换时不会注销其他账号.
struct AccountSwitcherSection: View {
    let profiles: [LibraryProfile]
    @Binding var selectedID: String
    let busy: Bool
    let hasSavedSession: (LibraryProfile) -> Bool
    let onAdd: () -> Void
    let addingAccount: Bool

    var body: some View {
        HStack(spacing: 10) {
            Picker("当前账号", selection: $selectedID) {
                ForEach(profiles) { profile in
                    Text(pickerLabel(for: profile)).tag(profile.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(busy)
            if !addingAccount {
                Button("添加账号", action: onAdd)
                    .disabled(busy)
            }
        }
    }

    private func pickerLabel(for profile: LibraryProfile) -> String {
        profile.title + " · " + sessionLabel(for: profile)
    }

    private func sessionLabel(for profile: LibraryProfile) -> String {
        if profile.isUnbound { return "本机书库" }
        return hasSavedSession(profile) ? "已登录" : "未登录"
    }
}
