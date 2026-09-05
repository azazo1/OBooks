import AppKit

protocol ReaderKeyboardExclusive: AnyObject {}

enum ReaderKeyNavigation {
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
    private static let escape: UInt16 = 53

    static func pageDirection(for event: NSEvent) -> Int? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { return nil }
        guard !modifiers.contains(.shift) else { return nil }
        switch event.specialKey {
        case .leftArrow, .upArrow: return -1
        case .rightArrow, .downArrow: return 1
        default: break
        }
        switch event.keyCode {
        case Self.leftArrow, Self.upArrow: return -1
        case Self.rightArrow, Self.downArrow: return 1
        default: return nil
        }
    }

    static func isFind(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              !modifiers.contains(.shift),
              !modifiers.contains(.option),
              !modifiers.contains(.control) else {
            return false
        }
        return event.charactersIgnoringModifiers?.lowercased() == "f"
    }

    static func isEscape(_ event: NSEvent) -> Bool {
        event.keyCode == Self.escape
    }

    static func isEditingText(in window: NSWindow?) -> Bool {
        guard let first = window?.firstResponder else { return false }
        if first is ReaderKeyboardExclusive { return true }
        if let textView = first as? NSTextView {
            return textView.isEditable || textView.isFieldEditor
        }
        return first is NSTextField
    }
}

extension Notification.Name {
    static let obooksSearchRequested = Notification.Name("OBooksSearchRequested")
}
