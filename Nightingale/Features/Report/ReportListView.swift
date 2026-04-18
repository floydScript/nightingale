import SwiftUI
import SwiftData

struct ReportListView: View {

    let fileStore: AudioFileStore

    @Query(sort: \SleepSession.startTime, order: .reverse) private var sessions: [SleepSession]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if sessions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session, fileStore: fileStore)
                            } label: {
                                SessionRow(session: session)
                            }
                            .listRowBackground(Theme.surface)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)
                }
            }
            .navigationTitle("报告")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 42))
                .foregroundStyle(Theme.textTertiary)
            Text("还没有记录")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
            Text("睡一晚，明早回来看报告")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding()
    }
}

private struct SessionRow: View {
    let session: SleepSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.startTime, style: .date)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(timeRangeText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(TimeFormat.duration(session.durationSeconds))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 4)
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: session.startTime)
        let end = session.endTime.map { formatter.string(from: $0) } ?? "进行中"
        return "\(start) – \(end)"
    }
}
