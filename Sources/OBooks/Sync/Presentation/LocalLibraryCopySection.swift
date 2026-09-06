import SwiftUI

/// 设置页底部的本机书库复制入口, 选择来源后复制到当前书库.
struct LocalLibraryCopySection: View {
    let sources: [LibraryProfile]
    let isBusy: Bool
    let status: String?
    let onCopy: (LibraryProfile) -> Void

    @State private var selectedID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("从本地书库复制", selection: $selectedID) {
                    ForEach(sources) { profile in
                        Text(profile.title).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isBusy)
                Button("复制") {
                    if let profile = selectedProfile {
                        onCopy(profile)
                    }
                }
                .disabled(isBusy || selectedProfile == nil)
            }
            if let status, !status.isEmpty {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: resolveSelection)
        .onChange(of: sources.map(\.id)) { _, _ in
            resolveSelection()
        }
    }

    private var selectedProfile: LibraryProfile? {
        sources.first { $0.id == selectedID }
    }

    private func resolveSelection() {
        if sources.contains(where: { $0.id == selectedID }) { return }
        selectedID = sources.first?.id ?? ""
    }
}
