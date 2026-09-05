import Foundation

struct ReaderPageTurnGesture {
    private(set) var translation: CGFloat = 0
    private(set) var velocity: CGFloat = 0
    private var lastTimestamp: TimeInterval?

    var direction: Int? {
        guard abs(translation) >= 6 else { return nil }
        return translation < 0 ? 1 : -1
    }

    mutating func update(delta: CGFloat, timestamp: TimeInterval) {
        if let lastTimestamp {
            let elapsed = timestamp - lastTimestamp
            velocity = elapsed > 0 && elapsed < 0.15 ? delta / elapsed : 0
        }
        translation += delta
        lastTimestamp = timestamp
    }

    func progress(direction: Int, extent: CGFloat) -> CGFloat {
        min(1, max(0, -CGFloat(direction) * translation / max(1, extent)))
    }

    func shouldCommit(direction: Int, extent: CGFloat, timestamp: TimeInterval) -> Bool {
        let distance = -CGFloat(direction) * translation
        let recentVelocity = timestamp - (lastTimestamp ?? timestamp) < 0.12 ? velocity : 0
        let forwardVelocity = -CGFloat(direction) * recentVelocity
        if forwardVelocity < -180 { return false }
        return distance >= max(1, extent) * 0.25
            || (distance >= 12 && forwardVelocity > 450)
    }
}
