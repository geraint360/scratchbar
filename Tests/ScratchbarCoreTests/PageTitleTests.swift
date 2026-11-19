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

final class ExportFileNameTests: XCTestCase {
    func testUsesFirstLineAsTxtName() {
        XCTAssertEqual(exportFileName(for: "The Cheshire Cat\nWould you tell me"), "The Cheshire Cat.txt")
    }

    func testReplacesCharactersFinderCantUse() {
        XCTAssertEqual(exportFileName(for: "ssh deploy@host: /var/log"), "ssh deploy@host- -var-log.txt")
    }

    func testBlankPageIsUntitled() {
        XCTAssertEqual(exportFileName(for: "  \n\n"), "Untitled.txt")
    }

    func testLongFirstLineIsShortenedWithoutEllipsis() {
        let name = exportFileName(for: String(repeating: "a", count: 300))
        XCTAssertEqual(name, String(repeating: "a", count: 80) + ".txt")
    }

    func testLeadingDotIsRemovedSoTheFileIsntHidden() {
        XCTAssertEqual(exportFileName(for: ".env notes"), "env notes.txt")
    }
}
