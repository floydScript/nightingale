import XCTest
@testable import Nightingale

final class ApneaDetectorTests: XCTestCase {

    // MARK: - Silence window detection

    func testSilenceBetweenTwoEventsIsFound() {
        let detector = ApneaDetector(minSilenceSeconds: 10)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let windows = detector.findSilenceWindows(
            start: t0,
            end: t0.addingTimeInterval(600),
            audioEvents: [
                .init(timestamp: t0.addingTimeInterval(60), duration: 2),
                .init(timestamp: t0.addingTimeInterval(120), duration: 2),
            ]
        )
        // 预期 3 段：[0,60]、[62,120]、[122,600]
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(windows[0].start, t0)
        XCTAssertEqual(windows[0].end, t0.addingTimeInterval(60))
        XCTAssertEqual(windows[1].start, t0.addingTimeInterval(62))
        XCTAssertEqual(windows[1].end, t0.addingTimeInterval(120))
        XCTAssertEqual(windows[2].start, t0.addingTimeInterval(122))
        XCTAssertEqual(windows[2].end, t0.addingTimeInterval(600))
    }

    func testShortGapIsNotASilenceWindow() {
        let detector = ApneaDetector(minSilenceSeconds: 10)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let windows = detector.findSilenceWindows(
            start: t0,
            end: t0.addingTimeInterval(30),
            audioEvents: [
                .init(timestamp: t0.addingTimeInterval(2), duration: 1),   // gap 2s from start
                .init(timestamp: t0.addingTimeInterval(5), duration: 1),   // gap 2s from prev
                .init(timestamp: t0.addingTimeInterval(9), duration: 1),   // gap 3s from prev
            ]
        )
        // 只有末尾 [10, 30] 这一段 ≥ 10s
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].start, t0.addingTimeInterval(10))
        XCTAssertEqual(windows[0].end, t0.addingTimeInterval(30))
    }

    func testNoEventsOneBigWindow() {
        let detector = ApneaDetector(minSilenceSeconds: 10)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let windows = detector.findSilenceWindows(
            start: t0,
            end: t0.addingTimeInterval(3600),
            audioEvents: []
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].start, t0)
        XCTAssertEqual(windows[0].end, t0.addingTimeInterval(3600))
    }

    // MARK: - SpO2 drop evaluation

    func testDropBelowThresholdNotEmitted() {
        let detector = ApneaDetector(
            minSilenceSeconds: 10,
            spo2WindowSeconds: 180,
            minSpO2Drop: 3.0
        )
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        // 整夜 SpO2 稳定在 97-98%，没下降
        let samples = stride(from: -300, through: 600, by: 60).map {
            ApneaDetector.Spo2Sample(
                timestamp: t0.addingTimeInterval(TimeInterval($0)),
                percent: 97.5
            )
        }
        let input = ApneaDetector.Input(
            sessionStart: t0.addingTimeInterval(-600),
            sessionEnd: t0.addingTimeInterval(900),
            audioEvents: [
                .init(timestamp: t0.addingTimeInterval(-60), duration: 2),
                .init(timestamp: t0.addingTimeInterval(60), duration: 2),  // 静默 60s
            ],
            spo2Samples: samples
        )
        let candidates = detector.detect(input)
        XCTAssertTrue(candidates.isEmpty)
    }

    func testDropAboveThresholdEmitsCandidate() {
        let detector = ApneaDetector(
            minSilenceSeconds: 10,
            spo2WindowSeconds: 180,
            minSpO2Drop: 3.0
        )
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        // baseline 样本（事件前）97-98%
        var samples: [ApneaDetector.Spo2Sample] = []
        for s in stride(from: -180, to: 0, by: 30) {
            samples.append(.init(
                timestamp: t0.addingTimeInterval(TimeInterval(s)),
                percent: 97.5
            ))
        }
        // trough 样本（静默窗口内 + 后）掉到 92%
        for s in stride(from: 10, through: 90, by: 30) {
            samples.append(.init(
                timestamp: t0.addingTimeInterval(TimeInterval(s)),
                percent: 92.0
            ))
        }

        let input = ApneaDetector.Input(
            sessionStart: t0.addingTimeInterval(-300),
            sessionEnd: t0.addingTimeInterval(600),
            audioEvents: [
                // 事件 1 在 t0 之前；事件 2 在 t0+100，中间 100s 静默
                .init(timestamp: t0.addingTimeInterval(-5), duration: 2),
                .init(timestamp: t0.addingTimeInterval(100), duration: 2),
            ],
            spo2Samples: samples
        )
        let candidates = detector.detect(input)
        // 应该至少检测到一个 drop 事件
        XCTAssertFalse(candidates.isEmpty, "Expected at least one apnea candidate")
        let c = candidates.first!
        XCTAssertGreaterThanOrEqual(c.spo2Drop, 3.0)
        XCTAssertGreaterThanOrEqual(c.confidence, 0.5)
        XCTAssertLessThanOrEqual(c.confidence, 1.0)
    }

    func testBigDropYieldsHigherConfidence() {
        let detector = ApneaDetector(
            minSilenceSeconds: 10,
            spo2WindowSeconds: 180,
            minSpO2Drop: 3.0
        )
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var samples: [ApneaDetector.Spo2Sample] = []
        for s in stride(from: -180, to: 0, by: 30) {
            samples.append(.init(
                timestamp: t0.addingTimeInterval(TimeInterval(s)),
                percent: 98.0
            ))
        }
        // 掉到 85%（15 个百分点）
        samples.append(.init(timestamp: t0.addingTimeInterval(20), percent: 85.0))

        let input = ApneaDetector.Input(
            sessionStart: t0.addingTimeInterval(-300),
            sessionEnd: t0.addingTimeInterval(200),
            audioEvents: [
                .init(timestamp: t0.addingTimeInterval(-2), duration: 1),
                .init(timestamp: t0.addingTimeInterval(50), duration: 1),
            ],
            spo2Samples: samples
        )
        let candidates = detector.detect(input)
        XCTAssertFalse(candidates.isEmpty)
        // Drop = 13 百分点 → confidence 被 clamp 到 1.0
        XCTAssertEqual(candidates.first!.confidence, 1.0, accuracy: 1e-6)
    }

    func testNoSpo2SamplesYieldsNothing() {
        let detector = ApneaDetector()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let input = ApneaDetector.Input(
            sessionStart: t0,
            sessionEnd: t0.addingTimeInterval(3600),
            audioEvents: [],
            spo2Samples: []
        )
        XCTAssertTrue(detector.detect(input).isEmpty)
    }
}
