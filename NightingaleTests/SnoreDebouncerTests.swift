import XCTest
@testable import Nightingale

final class SnoreDebouncerTests: XCTestCase {

    func testSingleDetectionProducesEventOnFlush() {
        var d = SnoreDebouncer(gapSeconds: 2.0)
        XCTAssertNil(d.feed(make(start: 0, dur: 1, conf: 0.8)))
        let merged = d.flush()
        XCTAssertEqual(merged, SnoreDebouncer.Merged(start: 0, duration: 1, confidence: 0.8))
    }

    func testCloseDetectionsMergeIntoSingleEvent() {
        var d = SnoreDebouncer(gapSeconds: 2.0)
        XCTAssertNil(d.feed(make(start: 0, dur: 1, conf: 0.75)))
        // gap = 0.5s (1 -> 1.5 < 2.0), 合并
        XCTAssertNil(d.feed(make(start: 1.5, dur: 1, conf: 0.9)))
        let merged = d.flush()
        XCTAssertEqual(merged?.start, 0)
        XCTAssertEqual(merged?.duration ?? 0, 2.5, accuracy: 1e-6)
        XCTAssertEqual(merged?.confidence, 0.9)
    }

    func testFarApartDetectionsSplit() {
        var d = SnoreDebouncer(gapSeconds: 2.0)
        XCTAssertNil(d.feed(make(start: 0, dur: 1, conf: 0.8)))
        // gap = 5s，切开
        let firstEmit = d.feed(make(start: 6, dur: 1, conf: 0.85))
        XCTAssertEqual(firstEmit, SnoreDebouncer.Merged(start: 0, duration: 1, confidence: 0.8))
        let tail = d.flush()
        XCTAssertEqual(tail, SnoreDebouncer.Merged(start: 6, duration: 1, confidence: 0.85))
    }

    func testChainOfThree() {
        var d = SnoreDebouncer(gapSeconds: 2.0)
        XCTAssertNil(d.feed(make(start: 0, dur: 1, conf: 0.75)))
        XCTAssertNil(d.feed(make(start: 1.5, dur: 1, conf: 0.85)))   // 合并入第一个
        // gap = 3s，切开第一事件
        let emitted = d.feed(make(start: 5.5, dur: 1, conf: 0.9))
        XCTAssertEqual(emitted?.start, 0)
        XCTAssertEqual(emitted?.duration ?? 0, 2.5, accuracy: 1e-6)
        XCTAssertEqual(emitted?.confidence, 0.85)
        let tail = d.flush()
        XCTAssertEqual(tail, SnoreDebouncer.Merged(start: 5.5, duration: 1, confidence: 0.9))
    }

    // MARK: - Helpers

    private func make(start: TimeInterval, dur: TimeInterval, conf: Double) -> SnoreDetector.Detection {
        SnoreDetector.Detection(streamTime: start, duration: dur, confidence: conf)
    }
}
