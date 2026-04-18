import XCTest
@testable import Nightingale

final class CertExpiryTests: XCTestCase {

    func testStatusStringShape() {
        // remainingDays 可能为 nil（依 bundle 元数据）；shortStatus 在二者情况下都应返回有意义字符串
        let s = CertExpiry.shortStatus()
        XCTAssertFalse(s.isEmpty)
    }

    func testShouldWarnFlagConsistentWithDays() {
        let d = CertExpiry.remainingDays()
        let shouldWarn = CertExpiry.shouldWarnOnHome()
        if let d {
            XCTAssertEqual(shouldWarn, d <= 2)
        } else {
            XCTAssertFalse(shouldWarn, "Unknown cert state should not warn")
        }
    }
}
