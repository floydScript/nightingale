import XCTest
@testable import Nightingale

final class NightmareDetectorTests: XCTestCase {

    // MARK: - Fixtures

    private func remSegment(from start: Double, to end: Double) -> NightmareDetector.StageSegment {
        NightmareDetector.StageSegment(
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            stage: "rem"
        )
    }

    private func deepSegment(from start: Double, to end: Double) -> NightmareDetector.StageSegment {
        NightmareDetector.StageSegment(
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            stage: "deep"
        )
    }

    private func hr(_ t: Double, _ bpm: Double) -> NightmareDetector.HRSample {
        .init(timestamp: Date(timeIntervalSince1970: t), bpm: bpm)
    }

    // MARK: - Happy path

    func testFlatHRYieldsNoCandidates() {
        let detector = NightmareDetector()
        let input = NightmareDetector.Input(
            hrSamples: (0..<20).map { hr(Double($0) * 30, 60) },
            stageSegments: [remSegment(from: 0, to: 600)]
        )
        XCTAssertTrue(detector.detect(input).isEmpty)
    }

    func testHighSpikeDuringREMProducesCandidate() {
        let detector = NightmareDetector(zThreshold: 2.0)
        // 基线 60 bpm，一次性飙到 120 bpm
        var samples: [NightmareDetector.HRSample] = []
        for t in stride(from: 0.0, through: 540.0, by: 30.0) {
            samples.append(hr(t, 60))
        }
        samples.append(hr(570, 120))

        let input = NightmareDetector.Input(
            hrSamples: samples,
            stageSegments: [remSegment(from: 0, to: 600)]
        )
        let candidates = detector.detect(input)
        XCTAssertEqual(candidates.count, 1)
        let c = candidates.first!
        XCTAssertEqual(c.peakBPM, 120)
        XCTAssertGreaterThan(c.zScore, 2.0)
        XCTAssertGreaterThanOrEqual(c.confidence, 0.5)
        XCTAssertLessThanOrEqual(c.confidence, 1.0)
    }

    func testSpikeOutsideREMIsIgnored() {
        let detector = NightmareDetector(zThreshold: 2.0)
        var samples: [NightmareDetector.HRSample] = []
        for t in stride(from: 0.0, through: 540.0, by: 30.0) {
            samples.append(hr(t, 60))
        }
        samples.append(hr(570, 120))  // 尖峰落在 deep 阶段

        let input = NightmareDetector.Input(
            hrSamples: samples,
            stageSegments: [deepSegment(from: 0, to: 600)]
        )
        XCTAssertTrue(detector.detect(input).isEmpty)
    }

    func testAdjacentSpikesAreMerged() {
        let detector = NightmareDetector(zThreshold: 2.0, mergeGapSeconds: 60)
        var samples: [NightmareDetector.HRSample] = []
        // baseline
        for t in stride(from: 0.0, through: 540.0, by: 30.0) {
            samples.append(hr(t, 60))
        }
        // 三个间隔 30s 的尖峰（< 60s gap），应合并为 1
        samples.append(hr(560, 110))
        samples.append(hr(590, 115))
        samples.append(hr(620, 125))

        let input = NightmareDetector.Input(
            hrSamples: samples,
            stageSegments: [remSegment(from: 0, to: 700)]
        )
        let candidates = detector.detect(input)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.peakBPM, 125)
        XCTAssertGreaterThan(candidates.first?.duration ?? 0, 30)
    }

    func testDistantSpikesAreSplit() {
        let detector = NightmareDetector(zThreshold: 2.0, mergeGapSeconds: 60)
        var samples: [NightmareDetector.HRSample] = []
        for t in stride(from: 0.0, through: 540.0, by: 30.0) {
            samples.append(hr(t, 60))
        }
        // 两个相距 > 60s 的尖峰
        samples.append(hr(10, 110))
        samples.append(hr(300, 115))

        let input = NightmareDetector.Input(
            hrSamples: samples,
            stageSegments: [remSegment(from: 0, to: 600)]
        )
        let candidates = detector.detect(input)
        XCTAssertEqual(candidates.count, 2)
    }

    func testInsufficientSamplesYieldsNothing() {
        let detector = NightmareDetector()
        let input = NightmareDetector.Input(
            hrSamples: [hr(0, 60), hr(30, 120)],  // 只有 2 个
            stageSegments: [remSegment(from: 0, to: 600)]
        )
        XCTAssertTrue(detector.detect(input).isEmpty)
    }

    func testNoREMSegmentsYieldsNothing() {
        let detector = NightmareDetector()
        var samples: [NightmareDetector.HRSample] = []
        for t in stride(from: 0.0, through: 540.0, by: 30.0) {
            samples.append(hr(t, 60))
        }
        samples.append(hr(570, 120))

        let input = NightmareDetector.Input(
            hrSamples: samples,
            stageSegments: []
        )
        XCTAssertTrue(detector.detect(input).isEmpty)
    }
}
