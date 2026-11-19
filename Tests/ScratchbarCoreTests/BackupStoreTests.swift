import XCTest
@testable import ScratchbarCore

final class BackupStoreTests: XCTestCase {
    private var folder: URL!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("BackupStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeStore() -> BackupStore {
        BackupStore(folder: folder, now: { [unowned self] in now })
    }

    func testBackupKeepsOnlyNewestFiveAsItSaves() {
        let store = makeStore()
        for i in 1...7 {
            store.backup(id: "p", text: "v\(i)", reason: .beforeRestore)
            now += 1
        }
        // No prune() call: the limit holds as backups are saved.
        XCTAssertEqual(store.versions(id: "p").map(\.text), ["v7", "v6", "v5", "v4", "v3"])
    }

    func testSavingABackupExpiresPagesDeletedOver30DaysAgo() {
        let store = makeStore()
        store.backup(id: "gone", text: "bye", reason: .beforeDelete)
        store.markDeleted(id: "gone")
        now += 29 * 86_400
        store.backup(id: "other", text: "x", reason: .beforeDelete)
        XCTAssertEqual(store.versions(id: "gone").count, 1)
        now += 2 * 86_400
        store.backup(id: "other", text: "y", reason: .beforeDelete)
        XCTAssertEqual(store.versions(id: "gone").count, 0)
    }

    func testIdenticalTextNotDuplicated() {
        let store = makeStore()
        store.backup(id: "p", text: "same", reason: .beforeRestore)
        now += 1000
        store.backup(id: "p", text: "same", reason: .beforeDelete)
        XCTAssertEqual(store.versions(id: "p").count, 1)
    }

    func testVersionsNewestFirst() {
        let store = makeStore()
        for i in 1...3 {
            store.backup(id: "p", text: "v\(i)", reason: .beforeRestore)
            now += 60
        }
        let versions = store.versions(id: "p")
        XCTAssertEqual(versions.map(\.text), ["v3", "v2", "v1"])
        XCTAssertEqual(versions.first?.date, Date(timeIntervalSince1970: 1_800_000_120))
    }

    func testDeletedPagePrunedAfter30Days() {
        let store = makeStore()
        store.backup(id: "gone", text: "bye", reason: .beforeDelete)
        store.markDeleted(id: "gone")
        now += 29 * 86_400
        store.prune()
        XCTAssertEqual(store.versions(id: "gone").count, 1)
        now += 2 * 86_400
        store.prune()
        XCTAssertEqual(store.versions(id: "gone").count, 0)
    }

    func testPagesWithBackupsShowsTitlesAndDeleted() {
        let store = makeStore()
        store.backup(id: "a", text: "Alpha\nmore", reason: .beforeRestore)
        store.backup(id: "b", text: "Beta", reason: .beforeDelete)
        store.markDeleted(id: "b")
        let pages = Dictionary(uniqueKeysWithValues: store.pagesWithBackups().map { ($0.id, $0) })
        XCTAssertEqual(pages["a"]?.title, "Alpha")
        XCTAssertEqual(pages["a"]?.deleted, false)
        XCTAssertEqual(pages["b"]?.deleted, true)
    }

    func testUnmarkDeletedOnRestore() {
        let store = makeStore()
        store.backup(id: "b", text: "Beta", reason: .beforeDelete)
        store.markDeleted(id: "b")
        store.unmarkDeleted(id: "b")
        XCTAssertEqual(store.pagesWithBackups().first?.deleted, false)
    }
}
