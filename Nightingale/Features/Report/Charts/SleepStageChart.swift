import SwiftUI
import Charts

struct SleepStageChart: View {
    let session: SleepSession

    struct StageSegment: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
        let stage: String
    }

    private var segments: [StageSegment] {
        let samples = session.sensorSamples.filter { $0.kind == .sleepStage }
        return samples.compactMap { s -> StageSegment? in
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

    var body: some View {
        let segs = segments
        if segs.isEmpty {
            EmptyChartPlaceholder(label: "无睡眠分期数据")
        } else {
            Chart(segs) { seg in
                BarMark(
                    xStart: .value("start", seg.start),
                    xEnd: .value("end", seg.end),
                    y: .value("stage", seg.stage)
                )
                .foregroundStyle(Self.stageColor(seg.stage))
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: ["awake", "rem", "core", "deep"])
            }
            .frame(height: 180)
        }
    }

    private static func stageColor(_ stage: String) -> Color {
        switch stage {
        case "deep": return Color(red: 0.3, green: 0.4, blue: 0.9)
        case "core": return Color(red: 0.5, green: 0.6, blue: 0.95)
        case "rem": return Color(red: 0.85, green: 0.5, blue: 0.9)
        case "awake": return Color(red: 0.9, green: 0.5, blue: 0.4)
        case "inBed": return Color(white: 0.4)
        default: return Color(white: 0.5)
        }
    }
}
