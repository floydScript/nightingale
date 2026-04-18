import Foundation
import SwiftData

@Model
final class SensorSample {
    var session: SleepSession?
    var timestamp: Date
    var kindRaw: String
    var value: Double
    /// 睡眠分期用：格式 "core|end=<epoch>"；其他传感器留 nil。
    var stringValue: String?

    var kind: SensorKind {
        get { SensorKind(rawValue: kindRaw) ?? .heartRate }
        set { kindRaw = newValue.rawValue }
    }

    init(
        session: SleepSession?,
        timestamp: Date,
        kind: SensorKind,
        value: Double,
        stringValue: String? = nil
    ) {
        self.session = session
        self.timestamp = timestamp
        self.kindRaw = kind.rawValue
        self.value = value
        self.stringValue = stringValue
    }
}
