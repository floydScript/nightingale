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
}
