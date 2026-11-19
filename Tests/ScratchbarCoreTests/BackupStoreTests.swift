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

    func testBackupIfDueRespects10Minutes() {
        let store = makeStore()
        store.backupIfDue(id: "p", text: "v1")
        now += 599
        store.backupIfDue(id: "p", text: "v2")
        XCTAssertEqual(store.versions(id: "p").map(\.text), ["v1"])
        now += 1
        store.backupIfDue(id: "p", text: "v3")
        XCTAssertEqual(store.versions(id: "p").map(\.text), ["v3", "v1"])
    }

    func testExplicitBackupIgnoresInterval() {
        let store = makeStore()
        store.backupIfDue(id: "p", text: "v1")
        now += 5
        store.backup(id: "p", text: "v2", reason: .beforeDelete)
        XCTAssertEqual(store.versions(id: "p").map(\.text), ["v2", "v1"])
    }

    func testIdenticalTextNotDuplicated() {
        let store = makeStore()
        store.backup(id: "p", text: "same", reason: .periodic)
        now += 1000
        store.backup(id: "p", text: "same", reason: .beforeDelete)
        store.backupIfDue(id: "p", text: "same")
        XCTAssertEqual(store.versions(id: "p").count, 1)
    }

    func testVersionsNewestFirst() {
        let store = makeStore()
        for i in 1...3 {
            store.backup(id: "p", text: "v\(i)", reason: .periodic)
            now += 60
        }
        let versions = store.versions(id: "p")
        XCTAssertEqual(versions.map(\.text), ["v3", "v2", "v1"])
        XCTAssertEqual(versions.first?.date, Date(timeIntervalSince1970: 1_800_000_120))
    }

    func testPruneKeepsNewest20() {
        let store = makeStore()
        for i in 1...25 {
            store.backup(id: "p", text: "v\(i)", reason: .periodic)
            now += 1
        }
        store.prune()
        let texts = store.versions(id: "p").map(\.text)
        XCTAssertEqual(texts.count, 20)
        XCTAssertEqual(texts.first, "v25")
        XCTAssertEqual(texts.last, "v6")
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
        store.backup(id: "a", text: "Alpha\nmore", reason: .periodic)
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
