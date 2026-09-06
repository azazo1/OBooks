import AppKit
import XCTest
@testable import OBooks

@MainActor
final class AppWindowConfigurationTests: XCTestCase {
    func testPrimaryStageBehaviorUsesManagedDocumentWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.collectionBehavior = [
            .auxiliary,
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
            .fullScreenDisallowsTiling
        ]

        AppWindowConfiguration.applyPrimaryStageBehavior(window)

        XCTAssertEqual(window.collectionBehavior, [.primary, .managed])
    }

    func testSettingsWindowStaysAbovePrimaryLibraryWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        AppWindowConfiguration.applyPrimaryStageBehavior(window)
        AppWindowConfiguration.applySettingsWindowBehavior(window)
        XCTAssertEqual(window.identifier, AppWindowConfiguration.settingsWindowID)
        XCTAssertEqual(window.level, .floating)
        XCTAssertFalse(window.collectionBehavior.contains(.primary))
        XCTAssertTrue(AppWindowConfiguration.belongsToSettingsSession(window))
        XCTAssertFalse(window.styleMask.contains(.resizable))
    }

    func testContentHeightChangeKeepsWindowTopEdge() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 80, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        let top = window.frame.maxY
        let next = AppWindowConfiguration.windowFrame(keepingTopOf: window, contentHeight: 180)
        XCTAssertEqual(next.maxY, top, accuracy: 0.5)
        XCTAssertEqual(window.contentRect(forFrameRect: next).height, 180, accuracy: 0.5)
    }

    func testReaderWindowBackgroundFollowsAppearance() {
        let dark = NSAppearance(named: .darkAqua)!
        let light = NSAppearance(named: .aqua)!
        XCTAssertEqual(
            AppWindowConfiguration.readerWindowBackgroundColor(appearance: dark),
            .black
        )
        XCTAssertEqual(
            AppWindowConfiguration.readerWindowBackgroundColor(appearance: light),
            .windowBackgroundColor
        )
    }
}
