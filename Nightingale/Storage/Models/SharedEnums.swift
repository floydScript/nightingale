import Foundation

/// 睡眠事件类型。Phase 1A 暂不使用，Phase 1B 接入打呼识别时启用。
enum EventType: String, Codable, CaseIterable {
    case snore
    case sleepTalk
    case suspectedApnea
    case nightmareSpike
}

/// 传感器数据类型。Phase 1A 暂不使用，Phase 1B 接入 HealthKit 时启用。
enum SensorKind: String, Codable, CaseIterable {
    case heartRate
    case hrv
    case spo2
    case sleepStage
    case temperature
    case bodyMovement
}

/// 录音状态机的状态。
enum RecorderState: Equatable {
    case idle
    case recording(startedAt: Date)
    case finalizing
    case failed(message: String)
}
