import XCTest
@testable import ScratchbarCore

final class PageStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PageStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func setModified(_ store: PageStore, _ id: String, _ seconds: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: seconds)], ofItemAtPath: store.url(for: id).path)
    }

    func testWriteThenRead() throws {
        let store = PageStore(folder: folder)
        try store.write("p1", text: "hello\nworld")
        XCTAssertEqual(try store.read("p1"), "hello\nworld")
    }

    func testListNewestFirst() throws {
        let store = PageStore(folder: folder)
        try store.write("old", text: "old")
        try store.write("new", text: "new")
        try store.write("mid", text: "mid")
        try setModified(store, "old", 1_000)
        try setModified(store, "mid", 2_000)
        try setModified(store, "new", 3_000)
        XCTAssertEqual(try store.list().map(\.id), ["new", "mid", "old"])
    }

    func testAnyTxtIsAPage() throws {
        let store = PageStore(folder: folder)
        try store.write("seed", text: "x")  // creates the folder
        try Data("dup".utf8).write(to: folder.appendingPathComponent("notes 2.txt"))
        try Data().write(to: folder.appendingPathComponent(".DS_Store"))
        try Data("md".utf8).write(to: folder.appendingPathComponent("readme.md"))
        XCTAssertEqual(Set(try store.list().map(\.id)), ["seed", "notes 2"])
    }

    func testDeleteUsesTrash() throws {
        var trashed: [URL] = []
        let store = PageStore(folder: folder, trash: { trashed.append($0) })
        try store.write("p1", text: "bye")
        try store.delete("p1")
        XCTAssertEqual(trashed, [store.url(for: "p1")])
        // The store hands the file to `trash` and does not remove it itself.
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: "p1").path))
    }

    func testRemoveDeletesWithoutTrash() throws {
        var trashed: [URL] = []
        let store = PageStore(folder: folder, trash: { trashed.append($0) })
        try store.write("p1", text: "x")
        try store.remove("p1")
        XCTAssertTrue(trashed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: "p1").path))
    }

    func testNonUTF8FileIsReadable() throws {
        let store = PageStore(folder: folder)
        try store.write("seed", text: "x")
        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: store.url(for: "latin"))
        XCTAssertEqual(try store.read("latin"), "café")
        XCTAssertEqual(try store.list().first { $0.id == "latin" }?.title, "café")
    }

    func testTitleSurvivesUTF8SplitAtPrefixBoundary() throws {
        let store = PageStore(folder: folder)
        // 1 + 2n bytes: the 8 KB title read ends half-way through an "é".
        try store.write("split", text: "a" + String(repeating: "é", count: 5_000))
        XCTAssertEqual(try store.list().first?.title, "a" + String(repeating: "é", count: 38) + "…")
    }

    func testLargePageRoundTrips() throws {
        let store = PageStore(folder: folder)
        let line = "2026-11-19T10:00:00Z INFO something happened in the log here\n"
        let big = String(repeating: line, count: 5_000_000 / line.utf8.count)
        try store.write("big", text: big)
        XCTAssertEqual(try store.read("big"), big)
    }

    func testListTitlesComeFromContent() throws {
        let store = PageStore(folder: folder)
        try store.write("a", text: "\nFirst line\nsecond")
        try store.write("b", text: "")
        let titles = Dictionary(uniqueKeysWithValues: try store.list().map { ($0.id, $0.title) })
        XCTAssertEqual(titles["a"], "First line")
        XCTAssertEqual(titles["b"], "Empty")
    }

    func testListOfMissingFolderIsEmpty() throws {
        XCTAssertEqual(try PageStore(folder: folder).list(), [])
    }

    func testNewIDIsUUID() {
        XCTAssertNotNil(UUID(uuidString: PageStore.newID()))
    }
}
