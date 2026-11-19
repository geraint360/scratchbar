import XCTest
@testable import ScratchbarCore

final class SaveSchedulerTests: XCTestCase {
    private var saved: [(id: String, text: String)] = []

    private func makeScheduler(delay: TimeInterval = 0.3) -> SaveScheduler {
        SaveScheduler(delay: delay) { [unowned self] id, text in saved.append((id, text)) }
    }

    func testCoalescesRapidEdits() {
        let s = makeScheduler()
        s.knownOnDisk.insert("p")
        s.textChanged(id: "p", text: "a")
        s.textChanged(id: "p", text: "ab")
        s.textChanged(id: "p", text: "abc")
        XCTAssertTrue(saved.isEmpty)
        let done = expectation(description: "saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(saved.map(\.text), ["abc"])
        XCTAssertFalse(s.hasPendingChanges)
    }

    func testFlushWritesPendingImmediately() {
        let s = makeScheduler()
        s.textChanged(id: "p", text: "last keystrokes")
        XCTAssertTrue(s.hasPendingChanges)
        s.flush()
        XCTAssertEqual(saved.map(\.text), ["last keystrokes"])
        XCTAssertFalse(s.hasPendingChanges)
        // The debounced save must not fire a second time afterwards.
        let done = expectation(description: "waited")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(saved.count, 1)
    }

    func testEmptyNewPageNotSaved() {
        let s = makeScheduler()
        s.textChanged(id: "new", text: "")
        s.flush()
        XCTAssertTrue(saved.isEmpty)
    }

    func testEmptyingAnExistingPageIsSaved() {
        let s = makeScheduler()
        s.knownOnDisk.insert("p")
        s.textChanged(id: "p", text: "")
        s.flush()
        XCTAssertEqual(saved.map(\.text), [""])
    }

    func testSavingANewPageMarksItKnown() {
        let s = makeScheduler()
        s.textChanged(id: "new", text: "hi")
        s.flush()
        XCTAssertTrue(s.knownOnDisk.contains("new"))
    }

    func testSwitchingPagesSavesBothPendingEdits() {
        let s = makeScheduler()
        s.textChanged(id: "a", text: "A")
        s.textChanged(id: "b", text: "B")
        s.flush()
        XCTAssertEqual(Set(saved.map(\.id)), ["a", "b"])
    }
}
