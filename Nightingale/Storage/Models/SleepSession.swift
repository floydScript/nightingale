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
}
