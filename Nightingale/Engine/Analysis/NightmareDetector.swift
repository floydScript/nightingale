import Foundation

/// 夜惊检测（Phase 3 · P3.5）。纯函数规则引擎，与 `ApneaDetector` 同等定位。
///
/// 规则：
///   1. 遍历 HealthKit 拉回的 `sleepStage` 样本，筛出 `"rem"` 的时间段
///      （`stringValue` 以 "rem|end=<epoch>" 编码，来自 `HealthKitSync.sleepStageName`）
///   2. 对每个 REM 段，取其时间范围内的所有 HR 样本
///      - 计算该段 HR 的 mean / stddev
///      - 标记任何 `hr > mean + 2σ` 的样本为 "spike"
///   3. 把连续 spike（相邻 ≤ 60s）合并为单个 event
///   4. confidence 由 z-score 线性映射：z=2 → 0.5，z=4+ → 1.0
///
/// 纯函数：输入 samples，输出 candidate list。不触 SwiftData / 不触网络 /
/// 不依赖 MainActor。可在 RecorderController.postProcess 里 main-thread 调用。
struct NightmareDetector {

    struct HRSample: Sendable {
        let timestamp: Date
        let bpm: Double
    }

    struct StageSegment: Sendable {
        let start: Date
        let end: Date
        let stage: String  // "core" / "deep" / "rem" / "awake" / …
    }

    struct Input: Sendable {
        let hrSamples: [HRSample]
        let stageSegments: [StageSegment]
    }

    struct Candidate: Equatable, Sendable {
        let start: Date
        let duration: TimeInterval
        let peakBPM: Double
        let zScore: Double
        let confidence: Double
    }

    // MARK: - Parameters

    /// z-score 阈值。超过它的 HR 样本会被视为 spike。
    let zThreshold: Double

    /// 合并相邻 spike 的最大间隔（秒）。
    let mergeGapSeconds: TimeInterval

    init(zThreshold: Double = 2.0, mergeGapSeconds: TimeInterval = 60) {
        self.zThreshold = zThreshold
        self.mergeGapSeconds = mergeGapSeconds
    }

    // MARK: - API

    func detect(_ input: Input) -> [Candidate] {
        let remSegments = input.stageSegments.filter { $0.stage == "rem" }
        guard !remSegments.isEmpty, !input.hrSamples.isEmpty else { return [] }

        var candidates: [Candidate] = []
        for seg in remSegments {
            let inSeg = input.hrSamples.filter {
                $0.timestamp >= seg.start && $0.timestamp <= seg.end
            }
            guard inSeg.count >= 4 else { continue }  // 太少样本算不出可靠 stddev

            let values = inSeg.map(\.bpm)
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
            let std = sqrt(variance)
            guard std > 0.0001 else { continue }  // 全平线没意义

            let spikes = inSeg.filter { ($0.bpm - mean) / std >= zThreshold }
            guard !spikes.isEmpty else { continue }

            candidates.append(contentsOf: mergeSpikes(spikes, mean: mean, std: std))
        }
        return candidates
    }

    // MARK: - Helpers

    /// 把连续 spike 合并成单个 Candidate；相邻 ≤ mergeGapSeconds 即视为同一事件。
    func mergeSpikes(_ spikes: [HRSample], mean: Double, std: Double) -> [Candidate] {
        let sorted = spikes.sorted { $0.timestamp < $1.timestamp }
        var out: [Candidate] = []
        var current: (start: Date, end: Date, peak: Double)?

        for s in sorted {
            if let cur = current, s.timestamp.timeIntervalSince(cur.end) <= mergeGapSeconds {
                current = (cur.start, s.timestamp, max(cur.peak, s.bpm))
            } else {
                if let cur = current {
                    out.append(makeCandidate(start: cur.start, end: cur.end, peak: cur.peak, mean: mean, std: std))
                }
                current = (s.timestamp, s.timestamp, s.bpm)
            }
        }
        if let cur = current {
            out.append(makeCandidate(start: cur.start, end: cur.end, peak: cur.peak, mean: mean, std: std))
        }
        return out
    }

    private func makeCandidate(start: Date, end: Date, peak: Double, mean: Double, std: Double) -> Candidate {
        let z = (peak - mean) / std
        // z=2 → 0.5，每多 1 σ 贡献 0.25；clamp 0.5...1.0
        let confidence = min(1.0, max(0.5, 0.5 + (z - zThreshold) * 0.25))
        return Candidate(
            start: start,
            duration: max(1, end.timeIntervalSince(start)),
            peakBPM: peak,
            zScore: z,
            confidence: confidence
        )
    }
}
