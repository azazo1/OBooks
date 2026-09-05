import AppKit
import SwiftUI

/// 关于面板, 展示应用信息与自动生成的构建版本.
///
/// 显示的版本号读取 Info.plist 中的 `CFBundleDisplayVersion`, 该值由
/// `scripts/dist-macos.sh` 在打包时根据 git 状态自动生成, 而不是写死:
/// - 恰好落在版本 tag 时显示该 tag, 如 `v1.2.3`.
/// - 处于非 tag commit 时显示 `最近tag-短hash`, 如 `v1.2.3-a1b2c3d`.
/// - 工作区有未提交改动时用 `^` 分隔, 如 `v1.2.3^a1b2c3d`.
struct AppAboutView: View {
    private var displayVersion: String {
        let bundle = Bundle.main
        let displayVersion = bundle.object(forInfoDictionaryKey: "CFBundleDisplayVersion") as? String
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let version = displayVersion ?? shortVersion ?? "未知版本"
        guard let buildNumber, !buildNumber.isEmpty else {
            return version
        }
        return "\(version) (\(buildNumber))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("OBooks")
                .font(.title2.bold())
            Text("macOS EPUB 阅读器")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(displayVersion)
                .font(.callout)
            Text("Copyright © 2026 azazo1")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 440)
    }
}
