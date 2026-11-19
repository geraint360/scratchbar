import XCTest
@testable import ScratchbarCore

final class SmokeTests: XCTestCase {
    func testPageKindExtension() {
        XCTAssertEqual(PageKind.text.rawValue, "txt")
    }
}
