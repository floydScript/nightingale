import XCTest
@testable import Nightingale

final class TimeFormatTests: XCTestCase {
    func testZeroSecondsFormats() {
        XCTAssertEqual(TimeFormat.duration(0), "0:00")
    }

    func testSecondsUnderMinute() {
        XCTAssertEqual(TimeFormat.duration(45), "0:45")
    }

    func testMinutesAndSeconds() {
        XCTAssertEqual(TimeFormat.duration(125), "2:05")
    }

    func testHoursMinutesSeconds() {
        XCTAssertEqual(TimeFormat.duration(3725), "1:02:05")
    }

    func testEightHoursTypicalNight() {
        XCTAssertEqual(TimeFormat.duration(8 * 3600 + 27 * 60 + 13), "8:27:13")
    }

    func testRejectsNegative() {
        XCTAssertEqual(TimeFormat.duration(-5), "0:00")
    }
}
