import Foundation
import SwiftData

@Model
final class SleepEvent {
    var id: UUID
    var session: SleepSession?
    var timestamp: Date
    var duration: TimeInterval
    /// 存 EventType.rawValue。SwiftData 对 @Attribute 存 enum 支持不稳定，转 String 更可靠。
    var typeRaw: String
    var confidence: Double
    var clipPath: String?
    var transcript: String?

    var type: EventType {
        get { EventType(rawValue: typeRaw) ?? .snore }
        set { typeRaw = newValue.rawValue }
    }

    init(
        session: SleepSession?,
        timestamp: Date,
        duration: TimeInterval,
        type: EventType,
        confidence: Double,
        clipPath: String? = nil,
        transcript: String? = nil
    ) {
        self.id = UUID()
        self.session = session
        self.timestamp = timestamp
        self.duration = duration
        self.typeRaw = type.rawValue
        self.confidence = confidence
        self.clipPath = clipPath
        self.transcript = transcript
    }
}
