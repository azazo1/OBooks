import AppKit
import OSLog
import UniformTypeIdentifiers

@MainActor
enum ReaderImageExporter {
    private static let logger = Logger(subsystem: "com.obooks.app", category: "reader.image-export")

    static func export(_ image: NSImage, from window: NSWindow? = nil) {
        let parentWindow = window ?? NSApp.keyWindow
        let panel = NSSavePanel()
        panel.title = "导出图片"
        panel.nameFieldStringValue = "图片.png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try writePNG(image, to: url)
                logger.info("图片导出完成")
            } catch {
                logger.error("图片导出失败: \(error.localizedDescription, privacy: .public)")
                let alert = NSAlert(error: error)
                alert.messageText = "图片导出失败"
                if let parentWindow {
                    alert.beginSheetModal(for: parentWindow)
                } else {
                    alert.runModal()
                }
            }
        }
        if let parentWindow {
            panel.beginSheetModal(for: parentWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    static func writePNG(_ image: NSImage, to url: URL) throws {
        guard !image.representations.isEmpty else { throw ExportError.encodingFailed }
        // 使用像素最多的原始位图, 避免阅读布局和预览缩放降低导出分辨率.
        let bitmap = image.representations.compactMap { $0 as? NSBitmapImageRep }.max {
            Double($0.pixelsWide) * Double($0.pixelsHigh) < Double($1.pixelsWide) * Double($1.pixelsHigh)
        } ?? image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }
        guard let data = bitmap?.representation(using: .png, properties: [:]) else {
            throw ExportError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private enum ExportError: LocalizedError {
        case encodingFailed

        var errorDescription: String? {
            "无法将此图片转换为 PNG 格式."
        }
    }
}
