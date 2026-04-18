import SwiftUI
import Charts

struct SnoreTimelineChart: View {
    let session: SleepSession

    var body: some View {
        let events = session.events
            .filter { $0.type == .snore }
            .sorted { $0.timestamp < $1.timestamp }

        if events.isEmpty {
            EmptyChartPlaceholder(label: "本晚未检测到打呼")
        } else {
            Chart(events) { e in
                PointMark(
                    x: .value("时间", e.timestamp),
                    y: .value("置信度", e.confidence)
                )
                .foregroundStyle(Theme.accent.opacity(0.85))
                .symbolSize(28)
            }
            .chartYScale(domain: 0.5...1.0)
            .chartYAxis {
                AxisMarks(values: [0.7, 0.8, 0.9, 1.0]) { v in
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text("\(Int(d * 100))%")
                        }
                    }
                    AxisGridLine()
                }
            }
            .frame(height: 120)
        }
    }
}
