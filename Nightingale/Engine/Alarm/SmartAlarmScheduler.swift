import Foundation
import UserNotifications
import HealthKit

/// 智能闹钟排期（Phase 3 · P3.1）。
///
/// 工作流：
/// 1. 用户在 AlarmView 设置：目标唤醒时间（如明早 07:00） + 窗口分钟数（10-30）
/// 2. 开始记录 / 每次进入 TonightView 时调用 `rescheduleIfNeeded(_:)`
/// 3. 我们先清掉已排的 Nightingale 通知，然后：
///    a. 查询 HealthKit 过去 4 小时的 sleepStage 数据
///    b. 在 [target-window, target] 区间内找第一个 light-sleep / awake 段 → 作为触发时刻
///    c. 没查到就 fallback 到硬目标时间
/// 4. 用 UNUserNotificationCenter schedule 一个本地通知
///
/// 所有 HealthKit I/O 都在 nonisolated 方法里做；对 UI 回调在 @MainActor。
@MainActor
final class SmartAlarmScheduler {

    private let healthStore = HKHealthStore()
    private let center = UNUserNotificationCenter.current()
    private static let notificationIdentifier = "com.floydscript.nightingale.smart-alarm"

    /// 申请通知权限。重入安全。
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            NSLog("Notification auth failed: \(error)")
            return false
        }
    }

    /// 根据 settings 排 / 重排闹钟。已关闭则清掉现有通知。
    /// 本次实现：一次性为"下一个 target 时间"排一个，用户每天重新进来刷新。
    func rescheduleIfNeeded(settings: AlarmSettings) async {
        await cancelAll()

        guard settings.isEnabled else {
            NSLog("SmartAlarm disabled; all notifications cancelled")
            return
        }

        let granted = await requestAuthorization()
        guard granted else {
            NSLog("SmartAlarm: notification permission denied")
            return
        }

        let target = nextTargetDate(hour: settings.targetHourMinute.0,
                                    minute: settings.targetHourMinute.1)
        let windowStart = target.addingTimeInterval(-Double(settings.windowMinutes) * 60)

        // 1. 尝试在 HealthKit 里找第一个 light-sleep 时刻
        let lightSleepFire = await findFirstLightSleep(
            between: windowStart,
            and: target
        )

        let fireDate = lightSleepFire ?? target
        await schedule(at: fireDate,
                       wasIdealized: lightSleepFire != nil,
                       target: target)
    }

    /// 彻底取消当前 app 排好的智能闹钟通知。
    func cancelAll() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }

    // MARK: - Scheduling helpers

    private func schedule(at fireDate: Date, wasIdealized: Bool, target: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "Nightingale 唤醒"
        if wasIdealized {
            content.body = "这是一个浅睡时刻，起床会更轻松。"
        } else {
            content.body = "到达你设置的最晚唤醒时间。"
        }
        content.sound = .default

        // 距离现在 < 0 视为立即（实际上 UN 不支持负数触发，用 1 秒兜底）
        let interval = max(1, fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: interval,
            repeats: false
        )
        let req = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(req)
            NSLog("SmartAlarm scheduled at \(fireDate) (idealized=\(wasIdealized))")
        } catch {
            NSLog("Failed to schedule smart alarm: \(error)")
        }
    }

    /// 计算下一个"目标时间"：若今天此时刻已过，则明天的同样时刻。
    private func nextTargetDate(hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        let today = cal.date(from: comps) ?? now
        if today > now {
            return today
        }
        return cal.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// 在 [start, end] 区间内查询 HealthKit，返回第一个 "light sleep" (asleepCore / awake)
    /// 段的起始时间。查询失败或区间空 → nil。
    private nonisolated func findFirstLightSleep(between start: Date, and end: Date) async -> Date? {
        guard HKHealthStore.isHealthDataAvailable(), end > start else { return nil }
        let store = HKHealthStore()
        let type = HKCategoryType(.sleepAnalysis)
        // 注意：我们不主动 requestAuthorization —— 由 HealthKitSync 统一管理。
        // 若用户没授权，query 返回空数组，逻辑降级为 nil → fallback 到 target。
        return await withCheckedContinuation { (cont: CheckedContinuation<Date?, Never>) in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                guard let categorySamples = samples as? [HKCategorySample] else {
                    cont.resume(returning: nil)
                    return
                }
                // 浅睡期定义：asleepCore 或 awake（苹果建议的"容易唤醒"时刻）
                let lightValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.awake.rawValue,
                ]
                let match = categorySamples.first { lightValues.contains($0.value) }
                cont.resume(returning: match?.startDate)
            }
            store.execute(query)
        }
    }
}
