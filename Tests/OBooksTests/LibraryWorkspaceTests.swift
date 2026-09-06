import Foundation
import XCTest
@testable import OBooks

@MainActor
final class LibraryWorkspaceTests: XCTestCase {
    func testSwitchingProfilesKeepsOtherAccountSession() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = URL(string: "http://127.0.0.1:1")!
        let workspace = try LibraryWorkspace(baseURL: directory)
        let alice = try seedAccount(workspace: workspace, server: server, username: "alice", title: "Alice Book", token: "alice-token")
        let bob = try seedAccount(workspace: workspace, server: server, username: "bob", title: "Bob Book", token: "bob-token")
        try workspace.setActive(alice.id)

        let model = AppModel(workspace: workspace, observeLifecycle: false)
        XCTAssertEqual(model.sync.account?.username, "alice")
        XCTAssertTrue(model.sync.isSignedIn)
        XCTAssertEqual(model.books.map(\.title), ["Alice Book"])
        XCTAssertTrue(model.hasSavedSession(for: alice))
        XCTAssertTrue(model.hasSavedSession(for: bob))

        model.switchToProfile(bob.id)
        XCTAssertNil(model.alert)
        XCTAssertEqual(workspace.activeID, bob.id)
        XCTAssertEqual(model.sync.account?.username, "bob")
        XCTAssertTrue(model.sync.isSignedIn)
        XCTAssertEqual(model.books.map(\.title), ["Bob Book"])
        XCTAssertEqual(try SyncCredentialStore(rootURL: workspace.root(for: alice.id)).read(), "alice-token")

        model.switchToProfile(alice.id)
        XCTAssertNil(model.alert)
        XCTAssertEqual(model.sync.account?.username, "alice")
        XCTAssertTrue(model.sync.isSignedIn)
        XCTAssertEqual(model.books.map(\.title), ["Alice Book"])

        await model.sync.logout()
        XCTAssertFalse(model.sync.isSignedIn)
        XCTAssertNil(try SyncCredentialStore(rootURL: workspace.root(for: alice.id)).read())
        XCTAssertEqual(try SyncCredentialStore(rootURL: workspace.root(for: bob.id)).read(), "bob-token")

        model.switchToProfile(bob.id)
        XCTAssertTrue(model.sync.isSignedIn)
        XCTAssertEqual(model.sync.account?.username, "bob")
        XCTAssertEqual(model.books.map(\.title), ["Bob Book"])
    }

    func testFailedNewLoginRestoresPreviousAccount() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = URL(string: "http://127.0.0.1:1")!
        let workspace = try LibraryWorkspace(baseURL: directory)
        let alice = try seedAccount(workspace: workspace, server: server, username: "alice", title: "Alice Book", token: "alice-token")
        try workspace.setActive(alice.id)

        let model = AppModel(workspace: workspace, observeLifecycle: false)
        let signedIn = await model.loginToAccount(server: "http://127.0.0.1:1", username: "carol", password: "secret")
        XCTAssertFalse(signedIn)
        XCTAssertEqual(workspace.activeID, alice.id)
        XCTAssertEqual(model.sync.account?.username, "alice")
        XCTAssertTrue(model.sync.isSignedIn)
        XCTAssertEqual(try SyncCredentialStore(rootURL: workspace.root(for: alice.id)).read(), "alice-token")
        XCTAssertEqual(model.books.map(\.title), ["Alice Book"])
        XCTAssertNil(workspace.profile(server: server, username: "carol"))
    }

    func testRemoveLocalAccountDeletesProfileAndKeepsOthers() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = URL(string: "http://127.0.0.1:1")!
        let workspace = try LibraryWorkspace(baseURL: directory)
        let alice = try seedAccount(workspace: workspace, server: server, username: "alice", title: "Alice Book", token: "alice-token")
        let bob = try seedAccount(workspace: workspace, server: server, username: "bob", title: "Bob Book", token: "bob-token")
        try workspace.setActive(alice.id)

        let model = AppModel(workspace: workspace, observeLifecycle: false)
        await model.removeLocalAccount(bob)
        XCTAssertNil(model.accountActionError)
        XCTAssertEqual(model.sync.account?.username, "alice")
        XCTAssertTrue(model.sync.isSignedIn)
        XCTAssertNil(workspace.profile(server: server, username: "bob"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.root(for: bob.id).path))
        XCTAssertEqual(try SyncCredentialStore(rootURL: workspace.root(for: alice.id)).read(), "alice-token")

        await model.removeLocalAccount(alice)
        XCTAssertNil(model.accountActionError)
        XCTAssertEqual(workspace.activeID, LibraryProfile.unboundID)
        XCTAssertNil(model.sync.account)
        XCTAssertNil(workspace.profile(server: server, username: "alice"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.root(for: alice.id).path))
        XCTAssertTrue(workspace.profiles.contains(where: \.isUnbound))

        await model.removeLocalAccount(try XCTUnwrap(workspace.activeProfile))
        XCTAssertEqual(model.accountActionError, "未绑定书库不能删除")
        XCTAssertEqual(workspace.activeID, LibraryProfile.unboundID)
    }

    private func seedAccount(
        workspace: LibraryWorkspace,
        server: URL,
        username: String,
        title: String,
        token: String
    ) throws -> LibraryProfile {
        let profile = try workspace.ensureAccountProfile(server: server, username: username)
        var journal = SyncJournal()
        journal.account = SyncAccount(server: server, username: username, userID: "user-" + username)
        try SyncJournalStore(rootURL: workspace.root(for: profile.id)).save(journal)
        try SyncCredentialStore(rootURL: workspace.root(for: profile.id)).write(token)
        let bookID = UUID()
        var book = BookSummary(
            id: bookID,
            title: title,
            authors: [],
            sortTitle: title.lowercased(),
            sourceFileName: "book.epub",
            folderName: bookID.uuidString,
            coverPath: nil,
            spine: [EPUBSpineItem(id: "chapter", href: "chapter.xhtml", title: "Chapter", linear: true)],
            toc: [],
            progressFraction: 0,
            lastOpenedAt: nil,
            importedAt: Date(timeIntervalSince1970: 1000)
        )
        book.canonicalID = String(repeating: username == "alice" ? "a" : "b", count: 64)
        XCTAssertTrue(LibraryStore(rootURL: workspace.root(for: profile.id)).save([book]))
        return profile
    }
}
