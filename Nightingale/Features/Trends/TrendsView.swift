import SwiftUI
import SwiftData
import Charts

/// 趋势 Tab：近 7 / 30 / 90 天的跨夜聚合图表。
/// 全部基于已入库的 SleepSession / SleepEvent / SensorSample，不做新的存储。
struct TrendsView: View {

    enum Window: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week: "7 天"
            case .month: "30 天"
            case .quarter: "90 天"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SleepSession.startTime, order: .reverse) private var sessions: [SleepSession]

    @State private var window: Window = .week

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        windowPicker

                        let filtered = sessionsInWindow()
                        if filtered.isEmpty {
                            emptyState
                        } else {
                            ahiCard(filtered)
                            sleepDurationCard(filtered)
                            snoreCountCard(filtered)
                            averageHRCard(filtered)
                            minSpo2Card(filtered)
                        }
                        Spacer().frame(height: 30)
                    }
                    .padding(.horizontal, Theme.padding)
                    .padding(.top, Theme.padding)
                }
            }
            .navigationTitle("趋势")
        }
    }

    // MARK: - Segmented window picker

    private var windowPicker: some View {
        Picker("", selection: $window) {
            ForEach(Window.allCases) { w in
                Text(w.label).tag(w)
            }
        }
        .pickerStyle(.segmented)
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)
            Text("还没有足够的记录")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Cards

    private func sleepDurationCard(_ sessions: [SleepSession]) -> some View {
        card(title: "平均睡眠时长", summary: durationSummary(sessions)) {
            let points = sessions.map { s in
                TrendPoint(date: startOfDay(s.startTime), value: s.durationSeconds / 3600.0)
            }
            Chart(points) { p in
                LineMark(
                    x: .value("日期", p.date),
                    y: .value("小时", p.value)
                )
                .foregroundStyle(Theme.accent)
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("日期", p.date),
                    y: .value("小时", p.value)
                )
                .foregroundStyle(Theme.accent)
            }
            .chartYScale(domain: 0...12)
            .frame(height: 140)
        }
    }

    private func snoreCountCard(_ sessions: [SleepSession]) -> some View {
        card(title: "每夜打呼次数", summary: snoreSummary(sessions)) {
            let points = sessions.map { s in
                TrendPoint(date: startOfDay(s.startTime), value: Double(s.snoreCount))
            }
            Chart(points) { p in
                BarMark(
                    x: .value("日期", p.date, unit: .day),
                    y: .value("次数", p.value)
                )
                .foregroundStyle(Theme.accent.opacity(0.85))
            }
            .frame(height: 140)
        }
    }

    private func averageHRCard(_ sessions: [SleepSession]) -> some View {
        card(title: "平均心率", summary: avgHRSummary(sessions)) {
            let points = sessions.compactMap { s -> TrendPoint? in
                guard let hr = s.averageHeartRate else { return nil }
                return TrendPoint(date: startOfDay(s.startTime), value: hr)
            }
            if points.isEmpty {
                Text("暂无心率数据")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(points) { p in
                    LineMark(
                        x: .value("日期", p.date),
                        y: .value("BPM", p.value)
                    )
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("日期", p.date),
                        y: .value("BPM", p.value)
                    )
                    .foregroundStyle(Theme.accent)
                }
                .chartYScale(domain: 40...100)
                .frame(height: 140)
            }
        }
    }

    private func minSpo2Card(_ sessions: [SleepSession]) -> some View {
        card(title: "每夜最低 SpO₂", summary: minSpo2Summary(sessions)) {
            let points = sessions.compactMap { s -> TrendPoint? in
                guard let sp = s.minSpO2 else { return nil }
                return TrendPoint(date: startOfDay(s.startTime), value: sp)
            }
            if points.isEmpty {
                Text("暂无血氧数据")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(points) { p in
                    LineMark(
                        x: .value("日期", p.date),
                        y: .value("SpO₂", p.value)
                    )
                    .foregroundStyle(Theme.accentSecondary)
                    .interpolationMethod(.stepCenter)
                    PointMark(
                        x: .value("日期", p.date),
                        y: .value("SpO₂", p.value)
                    )
                    .foregroundStyle(Theme.accentSecondary)
                }
                .chartYScale(domain: 80...100)
                .frame(height: 140)
            }
        }
    }

    private func ahiCard(_ sessions: [SleepSession]) -> some View {
        let estimates = sessions.compactMap { s -> Double? in
            let hours = s.durationSeconds / 3600.0
            guard hours > 0 else { return nil }
            let apneas = s.events.filter { $0.type == .suspectedApnea }.count
            return Double(apneas) / hours
        }
        let avg = estimates.isEmpty ? 0 : estimates.reduce(0, +) / Double(estimates.count)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("估算 AHI")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(format: "%.1f 次/小时", avg))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(ahiColor(avg))
            }
            Text(ahiSeverityLabel(avg))
                .font(.subheadline)
                .foregroundStyle(ahiColor(avg))
            Text("正常 <5 / 轻度 5-15 / 中度 15-30 / 重度 30+，仅供参考，非医疗诊断。")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: - Generic card wrapper

    @ViewBuilder
    private func card<Content: View>(
        title: String,
        summary: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(summary).font(.subheadline.monospaced()).foregroundStyle(Theme.textSecondary)
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: - Data shaping

    private struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private func sessionsInWindow() -> [SleepSession] {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -window.rawValue,
            to: startOfDay(Date())
        ) ?? Date.distantPast
        return sessions
            .filter { $0.startTime >= cutoff }
            .sorted { $0.startTime < $1.startTime }
    }

    private func startOfDay(_ d: Date) -> Date {
        Calendar.current.startOfDay(for: d)
    }

    // MARK: - Summary strings

    private func durationSummary(_ sessions: [SleepSession]) -> String {
        let hrs = sessions.map { $0.durationSeconds / 3600 }
        guard !hrs.isEmpty else { return "—" }
        let avg = hrs.reduce(0, +) / Double(hrs.count)
        return String(format: "均 %.1f h", avg)
    }

    private func snoreSummary(_ sessions: [SleepSession]) -> String {
        let total = sessions.reduce(0) { $0 + $1.snoreCount }
        return "累计 \(total)"
    }

    private func avgHRSummary(_ sessions: [SleepSession]) -> String {
        let vals = sessions.compactMap { $0.averageHeartRate }
        guard !vals.isEmpty else { return "—" }
        let avg = vals.reduce(0, +) / Double(vals.count)
        return String(format: "均 %.0f BPM", avg)
    }

    private func minSpo2Summary(_ sessions: [SleepSession]) -> String {
        let vals = sessions.compactMap { $0.minSpO2 }
        guard !vals.isEmpty else { return "—" }
        let worst = vals.min() ?? 0
        return String(format: "最低 %.0f%%", worst)
    }

    private func ahiSeverityLabel(_ ahi: Double) -> String {
        switch ahi {
        case ..<5: return "正常范围"
        case 5..<15: return "轻度"
        case 15..<30: return "中度"
        default: return "重度"
        }
    }

    private func ahiColor(_ ahi: Double) -> Color {
        switch ahi {
        case ..<5: return Theme.accent
        case 5..<15: return Color(red: 1.0, green: 0.85, blue: 0.35)
        case 15..<30: return Color(red: 1.0, green: 0.65, blue: 0.25)
        default: return Theme.danger
        }
    }
}
