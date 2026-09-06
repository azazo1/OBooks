import SwiftUI

/// 设置页中的已保存账号列表, 切换时不会注销其他账号.
struct AccountSwitcherSection: View {
    let profiles: [LibraryProfile]
    let activeID: String?
    let busy: Bool
    let hasSavedSession: (LibraryProfile) -> Bool
    let onSwitch: (LibraryProfile) -> Void
    let onAdd: () -> Void
    let addingAccount: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已保存的账号")
                .font(.headline)
            ForEach(profiles) { profile in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.title)
                            .font(.body)
                        Text(statusLabel(for: profile))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if profile.id == activeID {
                        Text("当前")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Button("切换") { onSwitch(profile) }
                            .disabled(busy)
                    }
                }
                .padding(.vertical, 2)
            }
            if !addingAccount {
                Button("添加账号", action: onAdd)
                    .disabled(busy)
            }
        }
    }

    private func statusLabel(for profile: LibraryProfile) -> String {
        if profile.id == activeID {
            return hasSavedSession(profile) ? "当前已登录" : (profile.isUnbound ? "当前书库" : "当前未登录")
        }
        if profile.isUnbound { return "本机独立书库" }
        return hasSavedSession(profile) ? "已登录" : "需重新登录"
    }
}
