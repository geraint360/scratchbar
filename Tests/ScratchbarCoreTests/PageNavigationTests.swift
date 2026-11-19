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

final class EditedDescriptionTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()
    private let locale = Locale(identifier: "en_GB")

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testTodayAndYesterdayAreLowercase() {
        let now = date(19, 15, 0)
        XCTAssertEqual(editedDescription(date(19, 11, 23), now: now, calendar: calendar, locale: locale), "today at 11:23")
        XCTAssertEqual(editedDescription(date(18, 9, 5), now: now, calendar: calendar, locale: locale), "yesterday at 09:05")
    }

    func testOlderDatesShowTheDate() {
        let now = date(19, 15, 0)
        XCTAssertEqual(editedDescription(date(2, 16, 40), now: now, calendar: calendar, locale: locale), "2 Nov 2026 at 16:40")
    }
}

final class MatchRangeTests: XCTestCase {
    func testFindsEveryMatchIgnoringCaseAndAccents() {
        let text = "Café notes: cafe, CAFÉ."
        XCTAssertEqual(matchRanges(of: "cafe", in: text),
                       [NSRange(location: 0, length: 4), NSRange(location: 12, length: 4), NSRange(location: 18, length: 4)])
    }

    func testBlankQueryOrNoMatchGivesNothing() {
        XCTAssertEqual(matchRanges(of: "  ", in: "anything"), [])
        XCTAssertEqual(matchRanges(of: "zzz", in: "anything"), [])
    }

    func testRangesAreUTF16ForEmoji() {
        XCTAssertEqual(matchRanges(of: "b", in: "😀 b"), [NSRange(location: 3, length: 1)])
    }
}
