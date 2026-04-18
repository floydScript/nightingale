import SwiftUI
import Charts

struct HeartRateChart: View {
    let session: SleepSession

    var body: some View {
        let samples = session.sensorSamples
            .filter { $0.kind == .heartRate }
            .sorted { $0.timestamp < $1.timestamp }

        if samples.isEmpty {
            EmptyChartPlaceholder(label: "无心率数据（戴 Watch 睡一晚后自动同步）")
        } else {
            Chart(samples) { s in
                LineMark(
                    x: .value("时间", s.timestamp),
                    y: .value("BPM", s.value)
                )
                .foregroundStyle(Theme.accent)
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 40...120)
            .frame(height: 140)
        }
    }
}
