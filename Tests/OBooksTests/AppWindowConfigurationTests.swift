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
}
