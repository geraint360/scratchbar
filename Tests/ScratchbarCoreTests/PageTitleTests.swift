import XCTest
@testable import ScratchbarCore

final class PageTitleTests: XCTestCase {
    func testFirstNonBlankLine() {
        XCTAssertEqual(pageTitle(for: "\n\n  ssh deploy@host  \nmore"), "ssh deploy@host")
    }

    func testEmpty() {
        XCTAssertEqual(pageTitle(for: ""), "Empty")
        XCTAssertEqual(pageTitle(for: " \n\t\n"), "Empty")
    }

    func testTitleEdgeCases() {
        XCTAssertEqual(pageTitle(for: "a\r\nb"), "a")
        let long = pageTitle(for: String(repeating: "x", count: 10_000))
        XCTAssertEqual(long, String(repeating: "x", count: 39) + "…")
        XCTAssertEqual(long.count, 40)
    }
}
