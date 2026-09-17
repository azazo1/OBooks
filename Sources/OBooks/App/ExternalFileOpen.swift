import Foundation
import OSLog

enum ExternalFileOpen {
    private static let logger = Logger(subsystem: "com.obooks.app", category: "file.open")

    static func acceptedURLs(from urls: [URL]) -> [URL] {
        urls.filter { url in
            url.isFileURL && url.pathExtension.lowercased() == "epub"
        }
    }

    static func logAccepted(_ urls: [URL]) {
        logger.info("收到外部打开: count=\(urls.count), files=\(urls.map(\.lastPathComponent).joined(separator: ", "), privacy: .public)")
    }
}

/// 缓存 Finder / 打开方式在 AppModel 就绪前送达的 EPUB.
/// 启动时系统可能先投递文件再创建 SwiftUI 状态对象.
@MainActor
final class ExternalFileOpenInbox {
    static let shared = ExternalFileOpenInbox()
    private static let duplicateWindow: TimeInterval = 1

    private var pending: [URL] = []
    private var recentlyHandled: [URL: Date] = [:]
    private var consumer: (([URL]) -> Void)?

    init() {}

    func attach(_ consumer: @escaping ([URL]) -> Void) {
        self.consumer = consumer
        flush()
    }

    func enqueue(_ urls: [URL]) {
        let accepted = ExternalFileOpen.acceptedURLs(from: urls).filter { !isDuplicate($0) }
        guard !accepted.isEmpty else { return }
        ExternalFileOpen.logAccepted(accepted)
        pending.append(contentsOf: accepted)
        flush()
    }

    private func isDuplicate(_ url: URL) -> Bool {
        let now = Date()
        recentlyHandled = recentlyHandled.filter { now.timeIntervalSince($0.value) < Self.duplicateWindow }
        if pending.contains(url) { return true }
        if let last = recentlyHandled[url], now.timeIntervalSince(last) < Self.duplicateWindow {
            return true
        }
        recentlyHandled[url] = now
        return false
    }

    private func flush() {
        guard let consumer, !pending.isEmpty else { return }
        let urls = pending
        pending.removeAll()
        consumer(urls)
    }
}
