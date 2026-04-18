import Foundation
import SwiftData

@Model
final class SleepSession {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var fullAudioPath: String?
    var isArchived: Bool
    var morningMood: String?
    var morningNote: String?

    // MARK: - Phase 3

    /// JSON-encoded `[String]` 标签数组。存 raw String 避免 SwiftData 对 [String] 的
    /// 迁移抖动；通过计算属性 `tags` 读写。旧记录默认空 "[]"。
    var tagsRaw: String = "[]"

    /// 环境噪音整夜平均 dB（相对 RMS）。nil 表示未采集。
    var ambientNoiseAverageDB: Double?

    /// 环境噪音整夜峰值 dB。nil 表示未采集。
    var ambientNoisePeakDB: Double?

    @Relationship(deleteRule: .cascade, inverse: \SleepEvent.session)
    var events: [SleepEvent] = []

    @Relationship(deleteRule: .cascade, inverse: \SensorSample.session)
    var sensorSamples: [SensorSample] = []

    init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date? = nil,
        fullAudioPath: String? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.fullAudioPath = fullAudioPath
        self.isArchived = isArchived
    }

    /// 录制时长（秒）。未结束则返回从开始到现在。
    var durationSeconds: TimeInterval {
        let end = endTime ?? Date()
        return max(0, end.timeIntervalSince(startTime))
    }

    // MARK: - Phase 1B 派生指标

    var snoreCount: Int {
        events.filter { $0.type == .snore }.count
    }

    var totalSnoreDuration: TimeInterval {
        events.filter { $0.type == .snore }.reduce(0) { $0 + $1.duration }
    }

    var averageHeartRate: Double? {
        let hr = sensorSamples.filter { $0.kind == .heartRate }.map(\.value)
        return hr.isEmpty ? nil : hr.reduce(0, +) / Double(hr.count)
    }

    var minSpO2: Double? {
        sensorSamples.filter { $0.kind == .spo2 }.map(\.value).min()
    }

    var maxHeartRate: Double? {
        sensorSamples.filter { $0.kind == .heartRate }.map(\.value).max()
    }

    // MARK: - Phase 3 · 标签访问器

    /// 读写 JSON 编码的标签数组。读失败返回 []；写失败保留旧值。
    var tags: [String] {
        get {
            guard let data = tagsRaw.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return arr
        }
        set {
            let unique = Array(NSOrderedSet(array: newValue)) as? [String] ?? newValue
            if let data = try? JSONEncoder().encode(unique),
               let s = String(data: data, encoding: .utf8) {
                tagsRaw = s
            }
        }
    }
}
