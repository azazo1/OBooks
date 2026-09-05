import AppKit
import XCTest
@testable import OBooks

final class ReaderKeyNavigationTests: XCTestCase {
    func testArrowKeysMapToPageDirection() throws {
        XCTAssertEqual(ReaderKeyNavigation.pageDirection(for: try key(ReaderKeyNavigation.leftArrow)), -1)
        XCTAssertEqual(ReaderKeyNavigation.pageDirection(for: try key(ReaderKeyNavigation.upArrow)), -1)
        XCTAssertEqual(ReaderKeyNavigation.pageDirection(for: try key(ReaderKeyNavigation.rightArrow)), 1)
        XCTAssertEqual(ReaderKeyNavigation.pageDirection(for: try key(ReaderKeyNavigation.downArrow)), 1)
    }

    func testModifiedArrowsAreIgnored() throws {
        XCTAssertNil(ReaderKeyNavigation.pageDirection(for: try key(ReaderKeyNavigation.downArrow, [.command])))
        XCTAssertNil(ReaderKeyNavigation.pageDirection(for: try key(ReaderKeyNavigation.downArrow, [.shift])))
        XCTAssertNil(ReaderKeyNavigation.pageDirection(for: try key(ReaderKeyNavigation.downArrow, [.option])))
    }

    func testCommandFIsFindShortcut() throws {
        XCTAssertTrue(ReaderKeyNavigation.isFind(try key(3, [.command], characters: "f")))
        XCTAssertFalse(ReaderKeyNavigation.isFind(try key(3, characters: "f")))
        XCTAssertFalse(ReaderKeyNavigation.isFind(try key(ReaderKeyNavigation.downArrow, [.command])))
    }

    func testEscapeKey() throws {
        XCTAssertTrue(ReaderKeyNavigation.isEscape(try key(53)))
        XCTAssertFalse(ReaderKeyNavigation.isEscape(try key(ReaderKeyNavigation.leftArrow)))
    }

    private func key(
        _ code: UInt16,
        _ modifiers: NSEvent.ModifierFlags = [],
        characters: String = ""
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code
        ))
    }
}
