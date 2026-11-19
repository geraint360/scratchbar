import XCTest
@testable import ScratchbarCore

final class URLCommandTests: XCTestCase {
    private func parse(_ s: String) -> URLCommand? { URLCommand.parse(URL(string: s)!) }

    func testParsesNewWithText() {
        XCTAssertEqual(parse("scratchbar://new?text=Hello%20world"), .newPage(text: "Hello world", hide: false))
    }

    func testHideFlag() {
        XCTAssertEqual(parse("scratchbar://new?text=x&hide"), .newPage(text: "x", hide: true))
        XCTAssertEqual(parse("scratchbar://new?hide=1&text=x"), .newPage(text: "x", hide: true))
    }

    func testKeepsPlusAndNewlines() {
        XCTAssertEqual(parse("scratchbar://new?text=a%2Bb%0Aline%202"), .newPage(text: "a+b\nline 2", hide: false))
    }

    func testRejectsUnknownHost() {
        XCTAssertNil(parse("scratchbar://delete?text=x"))
        XCTAssertNil(parse("other://new?text=x"))
    }

    func testRejectsOver1MB() {
        let big = String(repeating: "a", count: 1_048_577)
        XCTAssertNil(parse("scratchbar://new?text=\(big)"))
        let ok = String(repeating: "a", count: 1_048_576)
        XCTAssertEqual(parse("scratchbar://new?text=\(ok)"), .newPage(text: ok, hide: false))
    }

    func testMissingTextIsNil() {
        XCTAssertNil(parse("scratchbar://new"))
        XCTAssertNil(parse("scratchbar://new?text="))
    }
}
