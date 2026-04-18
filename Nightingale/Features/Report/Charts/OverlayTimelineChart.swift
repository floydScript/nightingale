import SwiftUI
import Charts

/// 多维度叠加时间轴：把睡眠分期 / 心率 / SpO2 / 各类事件画在同一条时间轴上。
/// 睡眠分期用 BarMark 做背景色带，HR / SpO2 双 Y 轴折线，各类事件用 PointMark。
///
/// 这是 Phase 2 报告页的"核心组件"，给用户一眼看清"打呼和 SpO2 跌的时间是不是对得上"。
struct OverlayTimelineChart: View {

    let session: SleepSession

    // 分期背景色
    private static let stageColors: [String: Color] = [
        "deep":  Color(red: 0.2, green: 0.3, blue: 0.75),
        "core":  Color(red: 0.35, green: 0.45, blue: 0.82),
        "rem":   Color(red: 0.75, green: 0.4, blue: 0.82),
        "awake": Color(red: 0.8, green: 0.4, blue: 0.35),
        "inBed": Color(white: 0.3),
    ]

    // 事件色板
    private static let eventColors: [EventType: Color] = [
        .snore:           Color(red: 1.0, green: 0.35, blue: 0.35),
        .sleepTalk:       Color(red: 0.45, green: 0.85, blue: 0.55),
        .suspectedApnea:  Color(red: 1.0, green: 0.65, blue: 0.25),
        .nightmareSpike:  Color(red: 0.85, green: 0.45, blue: 0.95),
    ]

    // 图例
    private var legendScale: KeyValuePairs<String, Color> {
        [
            "打呼": Self.eventColors[.snore]!,
            "梦话": Self.eventColors[.sleepTalk]!,
            "疑似呼吸暂停": Self.eventColors[.suspectedApnea]!,
        ]
    }

    var body: some View {
        let stages = stageSegments()
        let hr = sortedSamples(kind: .heartRate)
        let spo2 = sortedSamples(kind: .spo2)
        let events = session.events.sorted { $0.timestamp < $1.timestamp }

        if stages.isEmpty && hr.isEmpty && spo2.isEmpty && events.isEmpty {
            EmptyChartPlaceholder(label: "暂无可叠加数据")
        } else {
            Chart {
                // 分期背景色带
                ForEach(stages) { seg in
                    BarMark(
                        xStart: .value("start", seg.start),
                        xEnd: .value("end", seg.end),
                        y: .value("bg", 0),
                        height: 500
                    )
                    .foregroundStyle(Self.stageColors[seg.stage] ?? Color(white: 0.25))
                    .opacity(0.18)
                }

                // HR 折线（主 Y 轴）
                ForEach(hr) { s in
                    LineMark(
                        x: .value("时间", s.timestamp),
                        y: .value("HR", s.value),
                        series: .value("系列", "HR")
                    )
                    .foregroundStyle(by: .value("系列", "心率"))
                    .interpolationMethod(.catmullRom)
                }

                // SpO2 折线（副 Y 轴）
                ForEach(spo2) { s in
                    LineMark(
                        x: .value("时间", s.timestamp),
                        y: .value("SpO2", s.value),
                        series: .value("系列", "SpO2")
                    )
                    .foregroundStyle(by: .value("系列", "血氧"))
                    .interpolationMethod(.stepCenter)
                }

                // 事件点
                ForEach(events) { e in
                    PointMark(
                        x: .value("时间", e.timestamp),
                        y: .value("events", yForEvent(e, session: session))
                    )
                    .foregroundStyle(by: .value("事件", eventLegendKey(e)))
                    .symbolSize(44)
                }
            }
            .chartForegroundStyleScale([
                "心率": Theme.accent,
                "血氧": Theme.accentSecondary,
                "打呼": Self.eventColors[.snore]!,
                "梦话": Self.eventColors[.sleepTalk]!,
                "疑似呼吸暂停": Self.eventColors[.suspectedApnea]!,
            ])
            .chartYScale(domain: 40...120)
            .chartYAxis {
                AxisMarks(position: .leading, values: [40, 60, 80, 100, 120])
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .frame(height: 220)
        }
    }

    // MARK: - Data shaping

    private func sortedSamples(kind: SensorKind) -> [SensorSample] {
        session.sensorSamples
            .filter { $0.kind == kind }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private struct StageSegment: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
        let stage: String
    }

    private func stageSegments() -> [StageSegment] {
        session.sensorSamples
            .filter { $0.kind == .sleepStage }
            .compactMap { s -> StageSegment? in
                guard let sv = s.stringValue else { return nil }
                let parts = sv.split(separator: "|").map(String.init)
                let stage = parts.first ?? "unknown"
                var endDate = s.timestamp.addingTimeInterval(60)
                if let endPart = parts.first(where: { $0.hasPrefix("end=") }),
                   let epoch = Double(endPart.dropFirst(4)) {
                    endDate = Date(timeIntervalSince1970: epoch)
                }
                return StageSegment(start: s.timestamp, end: endDate, stage: stage)
            }
            .sorted { $0.start < $1.start }
    }

    /// 事件点画在一个固定高度区间（50-110），让它和 HR 范围视觉共存。
    /// 不同类型事件拉开 y 位置便于肉眼区分。
    private func yForEvent(_ e: SleepEvent, session: SleepSession) -> Double {
        switch e.type {
        case .snore: return 55
        case .sleepTalk: return 105
        case .suspectedApnea: return 115
        case .nightmareSpike: return 100
        }
    }

    private func eventLegendKey(_ e: SleepEvent) -> String {
        switch e.type {
        case .snore: return "打呼"
        case .sleepTalk: return "梦话"
        case .suspectedApnea: return "疑似呼吸暂停"
        case .nightmareSpike: return "夜惊"
        }
    }
}
