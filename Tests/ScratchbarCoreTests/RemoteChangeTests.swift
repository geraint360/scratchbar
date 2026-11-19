import XCTest
@testable import ScratchbarCore

final class RemoteChangeTests: XCTestCase {
    func testModifiedOtherPageReloadsListOnly() {
        XCTAssertEqual(decide(.modified(id: "b"), openPageID: "a", editorDirty: false), [.reloadList])
    }

    func testModifiedOpenCleanPageReloadsSilently() {
        XCTAssertEqual(decide(.modified(id: "a"), openPageID: "a", editorDirty: false), [.reloadList, .reloadOpenPage])
    }

    func testModifiedOpenDirtyPageShowsBanner() {
        XCTAssertEqual(decide(.modified(id: "a"), openPageID: "a", editorDirty: true), [.reloadList, .showEditedBanner])
    }

    func testDeletedOpenPageShowsDeletedBanner() {
        XCTAssertEqual(decide(.deleted(id: "a"), openPageID: "a", editorDirty: false), [.reloadList, .showDeletedBanner])
    }

    func testDeletedOtherPageReloadsList() {
        XCTAssertEqual(decide(.deleted(id: "b"), openPageID: "a", editorDirty: true), [.reloadList])
    }

    func testConflictAlwaysShowsBanner() {
        XCTAssertEqual(decide(.conflict(id: "a"), openPageID: "a", editorDirty: false), [.reloadList, .showEditedBanner])
        XCTAssertEqual(decide(.conflict(id: "a"), openPageID: "a", editorDirty: true), [.reloadList, .showEditedBanner])
    }

    func testResolveKeepBoth() {
        XCTAssertEqual(resolveConflict(current: "mine", other: "theirs", choice: .keepBoth),
                       "mine\n\n——— from another Mac ———\n\ntheirs")
    }

    func testResolveKeepOther() {
        XCTAssertEqual(resolveConflict(current: "mine", other: "theirs", choice: .keepOther), "theirs")
        XCTAssertEqual(resolveConflict(current: "mine", other: "theirs", choice: .keepThisMac), "mine")
    }

    func testSnapshotDiff() {
        let t0 = Date(timeIntervalSince1970: 0), t1 = Date(timeIntervalSince1970: 10)
        let old = FolderSnapshot(entries: ["a": .init(modified: t0, size: 1), "b": .init(modified: t0, size: 1), "c": .init(modified: t0, size: 1)])
        let new = FolderSnapshot(entries: ["a": .init(modified: t1, size: 1), "c": .init(modified: t0, size: 2), "d": .init(modified: t1, size: 1)])
        XCTAssertEqual(Set(new.changes(since: old)), [.modified(id: "a"), .deleted(id: "b"), .modified(id: "c"), .modified(id: "d")])
        XCTAssertEqual(new.changes(since: new), [])
    }

    func testSnapshotReadsFolderIncludingPlaceholders() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Snap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("a.txt"))
        try Data().write(to: folder.appendingPathComponent(".b.txt.icloud"))
        try Data().write(to: folder.appendingPathComponent(".DS_Store"))
        XCTAssertEqual(Set(FolderSnapshot(folder: folder).entries.keys), ["a", "b"])
    }

    func testPlaceholderListedAsDownloading() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Placeholder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PageStore(folder: folder)
        try store.write("real", text: "Real page")
        try Data().write(to: folder.appendingPathComponent(".abc.txt.icloud"))
        let page = try XCTUnwrap(try store.list().first { $0.id == "abc" })
        XCTAssertEqual(page.title, "Downloading…")
        XCTAssertTrue(page.isDownloading)
        XCTAssertFalse(try XCTUnwrap(try store.list().first { $0.id == "real" }).isDownloading)
    }

    func testSaveWouldOverwriteRemoteChange() {
        // Disk still has what we last saved: safe to write.
        XCTAssertFalse(saveWouldOverwriteRemoteChange(diskText: "v1", lastSavedText: "v1", newText: "v2"))
        // Someone else changed the file since: don't overwrite.
        XCTAssertTrue(saveWouldOverwriteRemoteChange(diskText: "theirs", lastSavedText: "v1", newText: "v2"))
        // Disk already equals what we're about to write: nothing lost.
        XCTAssertFalse(saveWouldOverwriteRemoteChange(diskText: "v2", lastSavedText: "v1", newText: "v2"))
        // File gone (or unreadable): writing recreates it, nothing lost.
        XCTAssertFalse(saveWouldOverwriteRemoteChange(diskText: nil, lastSavedText: "v1", newText: "v2"))
    }
}
