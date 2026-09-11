import AppKit
import XCTest

final class MenuBarHidingGeometryTests: XCTestCase {
    func testCollapsedLengthUsesTwiceWidestScreenAndIsBounded() {
        XCTAssertEqual(MenuBarHidingGeometry.collapsedSeparatorLength(screenWidths: [1_200, 1_800]), 3_600)
        XCTAssertEqual(MenuBarHidingGeometry.collapsedSeparatorLength(screenWidths: []), 1_000)
        XCTAssertEqual(MenuBarHidingGeometry.collapsedSeparatorLength(screenWidths: [100]), 500)
        XCTAssertEqual(MenuBarHidingGeometry.collapsedSeparatorLength(screenWidths: [8_000]), 10_000)
    }


    func testSeparatorMustBeLeftOfRecoveryArrow() {
        let separator = NSRect(x: 100, y: 900, width: 20, height: 24)
        let arrow = NSRect(x: 130, y: 900, width: 24, height: 24)

        XCTAssertTrue(MenuBarHidingGeometry.isSeparatorSafelyLeft(
            separatorFrame: separator, arrowFrame: arrow
        ))
        XCTAssertFalse(MenuBarHidingGeometry.isSeparatorSafelyLeft(
            separatorFrame: arrow, arrowFrame: separator
        ))
        XCTAssertFalse(MenuBarHidingGeometry.isSeparatorSafelyLeft(
            separatorFrame: nil, arrowFrame: arrow
        ))
        XCTAssertFalse(MenuBarHidingGeometry.isSeparatorSafelyLeft(
            separatorFrame: .zero, arrowFrame: arrow
        ))
    }
}
