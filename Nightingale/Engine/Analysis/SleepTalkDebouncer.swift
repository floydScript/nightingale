import Foundation

/// 合并 SoundAnalysis 产生的连续 "speech" classifications 为单一梦话事件。
/// 结构与行为与 `SnoreDebouncer` 一致：若新 detection 起点与当前 pending 事件末尾间隔
/// ≤ `gapSeconds`，则延伸事件；否则开启新事件并把旧事件吐出。
///
/// 注：梦话 gap 默认拉长到 3s，因为梦话常有停顿，过短会切得过碎。
struct SleepTalkDebouncer {

    struct Merged: Equatable, Sendable {
        let start: TimeInterval
        let duration: TimeInterval
        let confidence: Double
    }

    private var pending: (start: TimeInterval, lastEnd: TimeInterval, maxConf: Double)?
    let gapSeconds: TimeInterval

    init(gapSeconds: TimeInterval = 3.0) {
        self.gapSeconds = gapSeconds
    }

    /// 喂一个 detection。若并入当前 pending 返回 nil；若开启新事件返回上一个完成事件。
    mutating func feed(_ d: SleepTalkDetector.Detection) -> Merged? {
        let end = d.streamTime + d.duration
        if let p = pending, d.streamTime - p.lastEnd <= gapSeconds {
            pending = (p.start, max(end, p.lastEnd), max(p.maxConf, d.confidence))
            return nil
        }
        let out = pending.map {
            Merged(start: $0.start, duration: $0.lastEnd - $0.start, confidence: $0.maxConf)
        }
        pending = (d.streamTime, end, d.confidence)
        return out
    }

    /// 结束时调用，flush 最后一个待吐事件。
    mutating func flush() -> Merged? {
        let out = pending.map {
            Merged(start: $0.start, duration: $0.lastEnd - $0.start, confidence: $0.maxConf)
        }
        pending = nil
        return out
    }
}
