import Foundation
import HealthKit
import Combine

@MainActor
final class HealthKitSync: ObservableObject {

    enum AuthStatus { case notRequested, granted, denied, unavailable }

    @Published private(set) var authStatus: AuthStatus = .notRequested

    /// HealthKit 内部自带线程管理，HKHealthStore 本身已 Sendable，可以从任意线程调用。
    private let store = HKHealthStore()

    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.oxygenSaturation),
        HKCategoryType(.sleepAnalysis),
    ]

    init() {
        if !HKHealthStore.isHealthDataAvailable() {
            authStatus = .unavailable
        }
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            authStatus = .unavailable
            return false
        }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            authStatus = .granted
            return true
        } catch {
            authStatus = .denied
            NSLog("HealthKit auth failed: \(error)")
            return false
        }
    }

    /// 拉取时间段内的所有传感器样本（HR / HRV / SpO2 / 睡眠分期）。
    /// 返回未入库的 SensorSample；调用方设置 session 并 insert 到 ModelContext。
    func pullSamples(from start: Date, to end: Date) async -> [SensorSample] {
        async let hr = fetchQuantityRaw(
            type: HKQuantityType(.heartRate),
            unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
            from: start, to: end
        )
        async let hrv = fetchQuantityRaw(
            type: HKQuantityType(.heartRateVariabilitySDNN),
            unit: HKUnit.secondUnit(with: .milli),
            from: start, to: end
        )
        async let spo2 = fetchQuantityRaw(
            type: HKQuantityType(.oxygenSaturation),
            unit: HKUnit.percent(),
            from: start, to: end
        )
        async let stages = fetchSleepStagesRaw(from: start, to: end)

        let hrSamples = await hr
        let hrvSamples = await hrv
        let spo2Samples = await spo2
        let stageSamples = await stages

        var results: [SensorSample] = []
        for t in hrSamples {
            results.append(SensorSample(session: nil, timestamp: t.0, kind: .heartRate, value: t.1))
        }
        for t in hrvSamples {
            results.append(SensorSample(session: nil, timestamp: t.0, kind: .hrv, value: t.1))
        }
        for t in spo2Samples {
            results.append(SensorSample(session: nil, timestamp: t.0, kind: .spo2, value: t.1 * 100.0))
            // 注：HKUnit.percent() 返回 0-1 小数，×100 转成百分数便于图表显示
        }
        for t in stageSamples {
            results.append(SensorSample(session: nil, timestamp: t.0, kind: .sleepStage, value: t.1, stringValue: t.2))
        }
        return results
    }

    // MARK: - Raw fetchers (nonisolated，内部用异步回调)

    private nonisolated func fetchQuantityRaw(
        type: HKQuantityType,
        unit: HKUnit,
        from: Date,
        to: Date
    ) async -> [(Date, Double)] {
        await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let list = (samples as? [HKQuantitySample])?.map {
                    ($0.startDate, $0.quantity.doubleValue(for: unit))
                } ?? []
                cont.resume(returning: list)
            }
            store.execute(query)
        }
    }

    private nonisolated func fetchSleepStagesRaw(from: Date, to: Date) async -> [(Date, Double, String?)] {
        await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let list: [(Date, Double, String?)] = (samples as? [HKCategorySample])?.map {
                    let name = Self.sleepStageName($0.value)
                    let encoded: String = "\(name)|end=\($0.endDate.timeIntervalSince1970)"
                    return ($0.startDate, Double($0.value), encoded as String?)
                } ?? []
                cont.resume(returning: list)
            }
            store.execute(query)
        }
    }

    private nonisolated static func sleepStageName(_ v: Int) -> String {
        switch v {
        case HKCategoryValueSleepAnalysis.inBed.rawValue: return "inBed"
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return "asleepUnspecified"
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: return "core"
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return "deep"
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return "rem"
        case HKCategoryValueSleepAnalysis.awake.rawValue: return "awake"
        default: return "unknown"
        }
    }
}
