import AppKit

struct NativeReaderAppearance {
    let background: NSColor
    let foreground: NSColor
    let accent: NSColor
    let selection: NSColor
    let userHighlight: NSColor
    let speechHighlight: NSColor

    init(theme: ReadingTheme) {
        switch theme {
        case .original, .paper:
            background = NSColor(calibratedWhite: 0.985, alpha: 1)
            foreground = NSColor(calibratedWhite: 0.12, alpha: 1)
        case .quiet:
            background = NSColor(calibratedRed: 0.93, green: 0.92, blue: 0.89, alpha: 1)
            foreground = NSColor(calibratedRed: 0.22, green: 0.21, blue: 0.19, alpha: 1)
        case .bold:
            background = NSColor(calibratedWhite: 0.075, alpha: 1)
            foreground = NSColor(calibratedWhite: 0.94, alpha: 1)
        case .calm:
            background = NSColor(calibratedRed: 0.89, green: 0.85, blue: 0.76, alpha: 1)
            foreground = NSColor(calibratedRed: 0.23, green: 0.20, blue: 0.16, alpha: 1)
        case .focus:
            background = NSColor(calibratedRed: 0.035, green: 0.038, blue: 0.042, alpha: 1)
            foreground = NSColor(calibratedWhite: 0.92, alpha: 1)
        }
        accent = NSColor.controlAccentColor
        selection = NSColor.controlAccentColor.withAlphaComponent(0.28)
        userHighlight = NSColor.systemYellow.withAlphaComponent(0.42)
        speechHighlight = NSColor.systemBlue.withAlphaComponent(0.32)
    }
}
