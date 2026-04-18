import XCTest
@testable import Nightingale

final class SleepTalkDebouncerTests: XCTestCase {

    func testSingleDetectionProducesEventOnFlush() {
        var d = SleepTalkDebouncer(gapSeconds: 3.0)
        XCTAssertNil(d.feed(make(start: 0, dur: 1, conf: 0.8)))
        let merged = d.flush()
        XCTAssertEqual(merged, SleepTalkDebouncer.Merged(start: 0, duration: 1, confidence: 0.8))
    }

    func testCloseDetectionsMergeIntoSingleEvent() {
        var d = SleepTalkDebouncer(gapSeconds: 3.0)
        XCTAssertNil(d.feed(make(start: 0, dur: 1, conf: 0.72)))
        // gap = 2s，<= 3s → 合并
        XCTAssertNil(d.feed(make(start: 3, dur: 1, conf: 0.88)))
        let merged = d.flush()
        XCTAssertEqual(merged?.start, 0)
        XCTAssertEqual(merged?.duration ?? 0, 4, accuracy: 1e-6)
        XCTAssertEqual(merged?.confidence, 0.88)
    }

    func testFarApartDetectionsSplit() {
        var d = SleepTalkDebouncer(gapSeconds: 3.0)
        XCTAssertNil(d.feed(make(start: 0, dur: 1, conf: 0.8)))
        // gap = 10s，切开
        let firstEmit = d.feed(make(start: 11, dur: 1, conf: 0.85))
        XCTAssertEqual(firstEmit, SleepTalkDebouncer.Merged(start: 0, duration: 1, confidence: 0.8))
        let tail = d.flush()
        XCTAssertEqual(tail, SleepTalkDebouncer.Merged(start: 11, duration: 1, confidence: 0.85))
    }

    func testChainOfThree() {
        var d = SleepTalkDebouncer(gapSeconds: 3.0)
        XCTAssertNil(d.feed(make(start: 0, dur: 1, conf: 0.75)))
        XCTAssertNil(d.feed(make(start: 2, dur: 1, conf: 0.85)))   // 合并入第一个
        // gap = 5s，切开第一事件
        let emitted = d.feed(make(start: 8, dur: 1, conf: 0.9))
        XCTAssertEqual(emitted?.start, 0)
        XCTAssertEqual(emitted?.duration ?? 0, 3, accuracy: 1e-6)
        XCTAssertEqual(emitted?.confidence, 0.85)
        let tail = d.flush()
        XCTAssertEqual(tail, SleepTalkDebouncer.Merged(start: 8, duration: 1, confidence: 0.9))
    }

    // MARK: - Helpers

    private func make(start: TimeInterval, dur: TimeInterval, conf: Double) -> SleepTalkDetector.Detection {
        SleepTalkDetector.Detection(streamTime: start, duration: dur, confidence: conf)
    }
}
