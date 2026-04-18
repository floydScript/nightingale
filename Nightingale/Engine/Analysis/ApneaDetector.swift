import Foundation

/// 疑似呼吸暂停事件检测（规则引擎）。
///
/// 在录音结束、HealthKit 样本已经入库、但还没剪 clip 的时刻运行。
/// 输入只需要当晚的 `events`（打呼 + 梦话）以及 `sensorSamples`（SpO2）。
///
/// 规则（来自 spec §4.2）：
///   1. 扫描 session 时间轴，找"静默窗口"——相邻两个音频事件之间（snore/sleepTalk）
///      间隔 ≥ `minSilenceSeconds`（默认 10 秒）。
///      （真正的 RMS 计算过重；spec 允许降级为"分类器命中间隔"——这里就是这么做的）
///   2. 对每个静默窗口，在 ±`spo2WindowSeconds` 的 envelope 内取 SpO2 样本：
///        baseline = 窗口前 3 分钟的平均
///        trough   = 窗口本身 + 后 3 分钟的最低
///      若 `baseline - trough >= minSpO2Drop`（默认 3%），判定为一次可疑呼吸暂停。
///   3. confidence 由 drop 幅度线性映射到 0.5-1.0。
///
/// 纯函数：输入 events + samples + session 时间区间，输出待插入的新 `SleepEvent`。
/// 不接触 ModelContext / 不触网络 / 不依赖 MainActor，方便单测。
struct ApneaDetector {

    struct Input {
        let sessionStart: Date
        let sessionEnd: Date
        /// 已经存在的音频事件（打呼 + 梦话），按时间升序或任意顺序皆可。
        let audioEvents: [AudioEvent]
        /// SpO2 样本（百分比，0-100 范围）。按时间升序或任意顺序皆可。
        let spo2Samples: [Spo2Sample]
    }

    struct AudioEvent: Sendable {
        let timestamp: Date
        let duration: TimeInterval
    }

    struct Spo2Sample: Sendable {
        let timestamp: Date
        let percent: Double
    }

    struct Candidate: Equatable, Sendable {
        let start: Date
        let duration: TimeInterval
        let confidence: Double
        let spo2Drop: Double  // 百分点
    }

    // MARK: - Parameters

    let minSilenceSeconds: TimeInterval
    let spo2WindowSeconds: TimeInterval
    let minSpO2Drop: Double

    init(
        minSilenceSeconds: TimeInterval = 10,
        spo2WindowSeconds: TimeInterval = 180,
        minSpO2Drop: Double = 3.0
    ) {
        self.minSilenceSeconds = minSilenceSeconds
        self.spo2WindowSeconds = spo2WindowSeconds
        self.minSpO2Drop = minSpO2Drop
    }

    // MARK: - Detection

    func detect(_ input: Input) -> [Candidate] {
        let silenceWindows = findSilenceWindows(
            start: input.sessionStart,
            end: input.sessionEnd,
            audioEvents: input.audioEvents
        )
        guard !silenceWindows.isEmpty, !input.spo2Samples.isEmpty else { return [] }

        let sortedSpo2 = input.spo2Samples.sorted { $0.timestamp < $1.timestamp }

        return silenceWindows.compactMap { window -> Candidate? in
            guard let drop = evaluateDrop(in: window, samples: sortedSpo2) else {
                return nil
            }
            guard drop >= minSpO2Drop else { return nil }

            // 映射：drop 3% → 0.5, drop 8%+ → 1.0
            let confidence = min(1.0, 0.5 + (drop - minSpO2Drop) / 10.0)
            return Candidate(
                start: window.start,
                duration: window.end.timeIntervalSince(window.start),
                confidence: max(0.5, confidence),
                spo2Drop: drop
            )
        }
    }

    // MARK: - Helpers (internal 方便测试)

    struct SilenceWindow: Equatable {
        let start: Date
        let end: Date
    }

    /// 返回所有音频事件之间 ≥ minSilenceSeconds 的空白段。
    /// 包含 session 开头到第一个事件、最后一个事件到 session 结尾两端。
    func findSilenceWindows(
        start: Date,
        end: Date,
        audioEvents: [AudioEvent]
    ) -> [SilenceWindow] {
        guard end > start else { return [] }
        let sorted = audioEvents.sorted { $0.timestamp < $1.timestamp }

        var windows: [SilenceWindow] = []
        var cursor = start

        for event in sorted {
            let gap = event.timestamp.timeIntervalSince(cursor)
            if gap >= minSilenceSeconds {
                windows.append(SilenceWindow(start: cursor, end: event.timestamp))
            }
            let eventEnd = event.timestamp.addingTimeInterval(event.duration)
            if eventEnd > cursor { cursor = eventEnd }
        }

        // 最后一个事件到 session 结尾
        if end.timeIntervalSince(cursor) >= minSilenceSeconds {
            windows.append(SilenceWindow(start: cursor, end: end))
        }
        return windows
    }

    /// 计算某个静默窗口对应的 SpO2 下降幅度（百分点）。
    /// baseline = [start - spo2WindowSeconds, start) 平均
    /// trough   = [start, end + spo2WindowSeconds] 最低
    /// 返回 nil 表示无法评估（样本不足）。
    func evaluateDrop(
        in window: SilenceWindow,
        samples: [Spo2Sample]
    ) -> Double? {
        let baselineStart = window.start.addingTimeInterval(-spo2WindowSeconds)
        let troughEnd = window.end.addingTimeInterval(spo2WindowSeconds)

        let baselineSamples = samples.filter {
            $0.timestamp >= baselineStart && $0.timestamp < window.start
        }
        let troughSamples = samples.filter {
            $0.timestamp >= window.start && $0.timestamp <= troughEnd
        }
        guard !baselineSamples.isEmpty, !troughSamples.isEmpty else { return nil }

        let baseline = baselineSamples.map(\.percent).reduce(0, +) / Double(baselineSamples.count)
        guard let trough = troughSamples.map(\.percent).min() else { return nil }

        return baseline - trough
    }
}
