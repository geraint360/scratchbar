import XCTest
@testable import ScratchbarCore

final class PageNavigationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 0)

    private func page(_ id: String, _ title: String) -> Page {
        Page(id: id, modified: date, title: title)
    }

    // MARK: Search

    func testSearchMatchesTextCaseAndAccentInsensitively() {
        let pages = [page("a", "Shopping"), page("b", "Deploy"), page("c", "Notes")]
        let texts = ["a": "eggs\nmilk", "b": "ssh deploy@host", "c": "Café meeting"]
        let ids = matchingPageIDs(query: "CAFE", in: pages) { texts[$0] }
        XCTAssertEqual(ids, ["c"])
        XCTAssertEqual(matchingPageIDs(query: "milk", in: pages) { texts[$0] }, ["a"])
    }

    func testSearchFallsBackToTitleWhenTextUnreadable() {
        let pages = [page("a", "Shopping list"), page("b", "Deploy")]
        let ids = matchingPageIDs(query: "shop", in: pages) { _ in nil }
        XCTAssertEqual(ids, ["a"])
    }

    func testBlankQueryMatchesNothingSpecial() {
        let pages = [page("a", "x")]
        XCTAssertNil(matchingPageIDs(query: "  ", in: pages) { _ in "x" })
    }

    // MARK: ⌘[ / ⌘]

    func testAdjacentPageStopsAtEnds() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(adjacentPageID(in: ids, from: "b", offset: 1), "c")
        XCTAssertEqual(adjacentPageID(in: ids, from: "b", offset: -1), "a")
        XCTAssertNil(adjacentPageID(in: ids, from: "c", offset: 1))
        XCTAssertNil(adjacentPageID(in: ids, from: "a", offset: -1))
    }

    func testAdjacentPageFromNoneOrHiddenPageStartsAtAnEnd() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(adjacentPageID(in: ids, from: nil, offset: 1), "a")
        XCTAssertEqual(adjacentPageID(in: ids, from: "zz", offset: -1), "c")
        XCTAssertNil(adjacentPageID(in: [], from: nil, offset: 1))
    }
}
