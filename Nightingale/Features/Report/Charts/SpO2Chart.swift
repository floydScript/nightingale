import SwiftUI
import Charts

struct SpO2Chart: View {
    let session: SleepSession

    var body: some View {
        let samples = session.sensorSamples
            .filter { $0.kind == .spo2 }
            .sorted { $0.timestamp < $1.timestamp }

        if samples.isEmpty {
            EmptyChartPlaceholder(label: "无血氧数据")
        } else {
            Chart(samples) { s in
                LineMark(
                    x: .value("时间", s.timestamp),
                    y: .value("SpO₂", s.value)
                )
                .foregroundStyle(Theme.accentSecondary)
                .interpolationMethod(.stepCenter)
            }
            .chartYScale(domain: 85...100)
            .frame(height: 140)
        }
    }
}
