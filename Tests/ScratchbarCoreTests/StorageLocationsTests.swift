import XCTest
@testable import ScratchbarCore

/// Temp folders standing in for Application Support and the iCloud Drive root.
final class SyncFixture {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("SyncTests-\(UUID().uuidString)")
    var appSupport: URL { base.appendingPathComponent("AppSupport") }
    var cloudRoot: URL { base.appendingPathComponent("CloudDocs") }
    lazy var locations = StorageLocations(appSupport: appSupport, iCloudRoot: cloudRoot)

    init(cloudAvailable: Bool = true) {
        if cloudAvailable { makeCloudAvailable() }
    }

    func makeCloudAvailable() {
        try! FileManager.default.createDirectory(at: cloudRoot, withIntermediateDirectories: true)
    }

    func makeCloudUnavailable() {
        try? FileManager.default.removeItem(at: cloudRoot)
    }

    func files(in url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    func text(_ url: URL, _ name: String) -> String? {
        try? String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
    }

    deinit { try? FileManager.default.removeItem(at: base) }
}

final class StorageLocationsTests: XCTestCase {
    func testFolders() {
        let f = SyncFixture()
        XCTAssertEqual(f.locations.local.lastPathComponent, "Pages")
        XCTAssertEqual(f.locations.pending.lastPathComponent, "Pending")
        XCTAssertEqual(f.locations.backups.lastPathComponent, "Backups")
        XCTAssertEqual(f.locations.iCloud, f.cloudRoot.appendingPathComponent("Scratchbar", isDirectory: true))
    }

    func testWriteFallsBackToPendingWhenICloudUnavailable() throws {
        let f = SyncFixture()
        let repo = PageRepository(locations: f.locations, syncEnabled: true)
        try repo.write("a", text: "safe")
        XCTAssertFalse(repo.isDegraded)
        f.makeCloudUnavailable()
        try repo.write("b", text: "still safe")
        XCTAssertTrue(repo.isDegraded)
        XCTAssertEqual(f.files(in: f.locations.pending), ["b.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.cloudRoot.path), "must not recreate the iCloud root")
        XCTAssertEqual(try repo.read("b"), "still safe")
        let b = try repo.list().first { $0.id == "b" }
        XCTAssertEqual(b?.location, .pending)
    }

    func testFlushPendingMovesPagesWhenWritable() throws {
        let f = SyncFixture(cloudAvailable: false)
        let repo = PageRepository(locations: f.locations, syncEnabled: true)
        try repo.write("p", text: "offline edit")
        XCTAssertTrue(repo.isDegraded)
        f.makeCloudAvailable()
        XCTAssertEqual(repo.flushPending(), 1)
        XCTAssertFalse(repo.isDegraded)
        XCTAssertEqual(f.files(in: f.locations.pending), [])
        XCTAssertEqual(f.text(f.locations.iCloud!, "p.txt"), "offline edit")
    }

    func testFlushPendingKeepsBothWhenICloudChangedMeanwhile() throws {
        let f = SyncFixture(cloudAvailable: false)
        let repo = PageRepository(locations: f.locations, syncEnabled: true, macName: "Studio")
        try repo.write("p", text: "edited here offline")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)],
                                              ofItemAtPath: f.locations.pending.appendingPathComponent("p.txt").path)
        f.makeCloudAvailable()
        try FileManager.default.createDirectory(at: f.locations.iCloud!, withIntermediateDirectories: true)
        try Data("edited on the other Mac".utf8).write(to: f.locations.iCloud!.appendingPathComponent("p.txt"))
        repo.flushPending()
        XCTAssertEqual(f.text(f.locations.iCloud!, "p.txt"), "edited on the other Mac")
        XCTAssertEqual(f.text(f.locations.iCloud!, "p (from Studio).txt"), "edited here offline")
    }

    func testPendingCopyWinsOverOlderPrimary() throws {
        let f = SyncFixture()
        let repo = PageRepository(locations: f.locations, syncEnabled: true)
        try repo.write("p", text: "v1")
        f.makeCloudUnavailable()
        try repo.write("p", text: "v2")
        XCTAssertEqual(try repo.read("p"), "v2")
        XCTAssertEqual(try repo.list().filter { $0.id == "p" }.count, 1)
    }

    // Review C1: a Pending copy must not shadow edits once sync is off.
    func testSyncOffWriteReplacesStalePendingCopy() throws {
        let f = SyncFixture(cloudAvailable: false)
        try PageRepository(locations: f.locations, syncEnabled: true).write("a", text: "offline v1")
        let repo = PageRepository(locations: f.locations, syncEnabled: false)
        try repo.write("a", text: "v2 typed after turning sync off")
        XCTAssertEqual(try repo.read("a"), "v2 typed after turning sync off")
        XCTAssertEqual(f.files(in: f.locations.pending), [])
    }

    func testSyncOffFlushPendingMovesIntoLocal() throws {
        let f = SyncFixture(cloudAvailable: false)
        try PageRepository(locations: f.locations, syncEnabled: true).write("a", text: "offline")
        let repo = PageRepository(locations: f.locations, syncEnabled: false)
        XCTAssertEqual(repo.flushPending(), 1)
        XCTAssertEqual(f.text(f.locations.local, "a.txt"), "offline")
        XCTAssertEqual(f.files(in: f.locations.pending), [])
    }

    // Review I2: never overwrite iCloud text without a backup; unreadable → keep both.
    func testFlushPendingBacksUpOverwrittenICloudText() throws {
        let f = SyncFixture(cloudAvailable: false)
        var backedUp: [String] = []
        let repo = PageRepository(locations: f.locations, syncEnabled: true, macName: "Studio")
        repo.backup = { _, text in backedUp.append(text) }
        try repo.write("p", text: "newer offline edit")
        f.makeCloudAvailable()
        try FileManager.default.createDirectory(at: f.locations.iCloud!, withIntermediateDirectories: true)
        let cloudFile = f.locations.iCloud!.appendingPathComponent("p.txt")
        try Data("older cloud text".utf8).write(to: cloudFile)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: cloudFile.path)
        repo.flushPending()
        XCTAssertEqual(f.text(f.locations.iCloud!, "p.txt"), "newer offline edit")
        XCTAssertEqual(backedUp, ["older cloud text"])
    }

    func testFlushPendingKeepsBothWhenICloudUnreadable() throws {
        let f = SyncFixture(cloudAvailable: false)
        let repo = PageRepository(locations: f.locations, syncEnabled: true, macName: "Studio")
        try repo.write("p", text: "offline edit")
        f.makeCloudAvailable()
        try FileManager.default.createDirectory(at: f.locations.iCloud!, withIntermediateDirectories: true)
        let cloudFile = f.locations.iCloud!.appendingPathComponent("p.txt")
        try Data("their text".utf8).write(to: cloudFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: cloudFile.path)  // write-only: unreadable
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cloudFile.path) }
        repo.flushPending()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cloudFile.path)
        XCTAssertEqual(f.text(f.locations.iCloud!, "p.txt"), "their text")
        XCTAssertEqual(f.text(f.locations.iCloud!, "p (from Studio).txt"), "offline edit")
    }

    func testSyncOffNeverTouchesICloud() throws {
        let f = SyncFixture()
        let repo = PageRepository(locations: f.locations, syncEnabled: false)
        try repo.write("p", text: "local")
        XCTAssertEqual(f.files(in: f.locations.local), ["p.txt"])
        XCTAssertEqual(f.files(in: f.cloudRoot), [])
        XCTAssertFalse(repo.isDegraded)
    }
}

final class SyncMigratorTests: XCTestCase {
    private func writeLocal(_ f: SyncFixture, _ name: String, _ text: String) throws {
        try FileManager.default.createDirectory(at: f.locations.local, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: f.locations.local.appendingPathComponent(name))
    }

    private func writeCloud(_ f: SyncFixture, _ name: String, _ text: String) throws {
        try FileManager.default.createDirectory(at: f.locations.iCloud!, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: f.locations.iCloud!.appendingPathComponent(name))
    }

    func testEnableMovesPagesAndBacksUp() throws {
        let f = SyncFixture()
        try writeLocal(f, "a.txt", "alpha")
        let backups = BackupStore(folder: f.locations.backups)
        try SyncMigrator.enable(locations: f.locations, backups: backups, macName: "Studio")
        XCTAssertEqual(f.files(in: f.locations.local), [])
        XCTAssertEqual(f.text(f.locations.iCloud!, "a.txt"), "alpha")
        XCTAssertEqual(backups.versions(id: "a").first?.text, "alpha")
    }

    func testEnableDedupesIdenticalText() throws {
        let f = SyncFixture()
        try writeLocal(f, "a.txt", "same")
        try writeCloud(f, "a.txt", "same")
        try writeLocal(f, "b.txt", "shared text")
        try writeCloud(f, "x.txt", "shared text")
        try SyncMigrator.enable(locations: f.locations, backups: BackupStore(folder: f.locations.backups), macName: "Studio")
        XCTAssertEqual(f.files(in: f.locations.iCloud!), ["a.txt", "x.txt"])
    }

    func testEnableKeepsBothOnDifferentText() throws {
        let f = SyncFixture()
        try writeLocal(f, "a.txt", "from this Mac")
        try writeCloud(f, "a.txt", "from the other Mac")
        try SyncMigrator.enable(locations: f.locations, backups: BackupStore(folder: f.locations.backups), macName: "Studio")
        XCTAssertEqual(f.text(f.locations.iCloud!, "a.txt"), "from the other Mac")
        XCTAssertEqual(f.text(f.locations.iCloud!, "a (from Studio).txt"), "from this Mac")
    }

    // Review I4: a failure partway through must not remove any local page.
    func testEnableFailingPartwayKeepsAllLocalPages() throws {
        let f = SyncFixture()
        try writeLocal(f, "a.txt", "alpha")
        try writeLocal(f, "b.txt", "beta")
        let failing = FailingStore(wrapping: PageStore(folder: f.locations.iCloud!), failOnWrite: 2)
        XCTAssertThrowsError(try SyncMigrator.enable(locations: f.locations, backups: BackupStore(folder: f.locations.backups),
                                                     macName: "Studio", cloudStore: failing))
        XCTAssertEqual(f.files(in: f.locations.local), ["a.txt", "b.txt"])
    }

    func testEnableFailsWhenICloudUnavailable() throws {
        let f = SyncFixture(cloudAvailable: false)
        try writeLocal(f, "a.txt", "alpha")
        XCTAssertThrowsError(try SyncMigrator.enable(locations: f.locations, backups: BackupStore(folder: f.locations.backups), macName: "Studio"))
        XCTAssertEqual(f.files(in: f.locations.local), ["a.txt"])
    }

    func testDisableCopiesBackAndLeavesICloudIntact() throws {
        let f = SyncFixture()
        try writeCloud(f, "a.txt", "alpha")
        try writeCloud(f, "b.txt", "beta")
        try writeLocal(f, "b.txt", "old local beta")
        let backups = BackupStore(folder: f.locations.backups)
        try SyncMigrator.disable(locations: f.locations, backups: backups)
        XCTAssertEqual(f.files(in: f.locations.iCloud!), ["a.txt", "b.txt"])
        XCTAssertEqual(f.text(f.locations.local, "a.txt"), "alpha")
        XCTAssertEqual(f.text(f.locations.local, "b.txt"), "beta")
        XCTAssertEqual(backups.versions(id: "b").first?.text, "old local beta", "overwritten local copy is backed up")
    }
}

/// A store whose Nth write throws.
final class FailingStore: PageStoring {
    let inner: PageStore
    let failOnWrite: Int
    private var writes = 0
    init(wrapping inner: PageStore, failOnWrite: Int) { self.inner = inner; self.failOnWrite = failOnWrite }
    func list() throws -> [Page] { try inner.list() }
    func read(_ id: String) throws -> String { try inner.read(id) }
    func write(_ id: String, text: String) throws {
        writes += 1
        if writes == failOnWrite { throw CocoaError(.fileWriteUnknown) }
        try inner.write(id, text: text)
    }
    func delete(_ id: String) throws { try inner.delete(id) }
    func remove(_ id: String) throws { try inner.remove(id) }
}
