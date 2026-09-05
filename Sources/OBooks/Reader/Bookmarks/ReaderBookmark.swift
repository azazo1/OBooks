import Foundation

struct ReaderBookmark: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let position: ReadingPosition
    let title: String
    let progressFraction: Double

    init(position: ReadingPosition, title: String, progressFraction: Double) {
        id = UUID()
        self.position = position
        self.title = title
        self.progressFraction = min(max(progressFraction, 0), 1)
    }

    func matches(_ position: ReadingPosition) -> Bool {
        // 同一正文位置的视口偏移可能随排版变化, 不作为书签身份的一部分.
        self.position.spineID == position.spineID
            && self.position.characterOffset == position.characterOffset
    }
}
