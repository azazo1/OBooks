import Foundation

struct EPUBSpineItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let href: String
    let title: String
    let linear: Bool
    var identity: String { id }
}

struct EPUBTOCItem: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var label: String
    var href: String
    var children: [EPUBTOCItem]
    init(label: String, href: String, children: [EPUBTOCItem] = []) {
        id = UUID(); self.label = label; self.href = href; self.children = children
    }
}

struct EPUBPackageInfo {
    let title: String
    let authors: [String]
    let spine: [EPUBSpineItem]
    let toc: [EPUBTOCItem]
    let coverPath: String?
}

enum EPUBImportError: LocalizedError, Equatable {
    case invalidFile
    case unsafeArchivePath(String)
    case archiveCommandFailed(String)
    case missingContainer
    case missingPackage
    case invalidPackage(String)
    case encryptedPublication

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "文件不是有效的 EPUB"
        case .unsafeArchivePath(let path): return "EPUB 包含不安全的文件路径: \(path)"
        case .archiveCommandFailed(let message): return "解包 EPUB 失败: \(message)"
        case .missingContainer: return "EPUB 缺少 META-INF/container.xml"
        case .missingPackage: return "找不到 EPUB 的 OPF 包文件"
        case .invalidPackage(let message): return "EPUB 包结构无效: \(message)"
        case .encryptedPublication: return "OBooks 暂不支持加密或 DRM 保护的 EPUB"
        }
    }
}
