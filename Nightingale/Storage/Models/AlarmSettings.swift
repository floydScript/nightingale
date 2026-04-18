import Foundation
import SwiftData

/// 智能闹钟设置（Phase 3 · P3.1）。
/// 单行模型：整个 app 只有一条记录（通过 `fetchSingleton(_:)` 保证）。
/// 存储用户设定的目标唤醒时间 + 窗口分钟数 + 启用开关。
@Model
final class AlarmSettings {
    var id: UUID

    /// 是否启用智能闹钟。关闭时 `SmartAlarmScheduler` 不会排任何通知。
    var isEnabled: Bool

    /// 最晚唤醒时分（Date；日期部分忽略，只读 hour/minute）。默认 07:00。
    var targetTime: Date

    /// 起床窗口分钟数（10-30）。最晚时间往前这么多分钟内找一次"浅睡"触发。
    var windowMinutes: Int

    init(
        id: UUID = UUID(),
        isEnabled: Bool = false,
        targetTime: Date = AlarmSettings.defaultTargetTime,
        windowMinutes: Int = 20
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.targetTime = targetTime
        self.windowMinutes = windowMinutes
    }

    /// 默认目标时间：今天 07:00。用户打开 AlarmView 会看到这个预设。
    static var defaultTargetTime: Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 7
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    /// 目标时分（小时, 分钟）元组。
    var targetHourMinute: (Int, Int) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: targetTime)
        return (comps.hour ?? 7, comps.minute ?? 0)
    }
}
