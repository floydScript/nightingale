import SwiftUI
import SwiftData
import AVFoundation
import Combine

/// 档案馆 Tab：跨 session 的事件总览 + 归档的整夜列表。
/// 以事件为主入口；同时把手动归档的夜晚置顶显示。
struct ArchiveView: View {

    let fileStore: AudioFileStore

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SleepEvent.timestamp, order: .reverse) private var allEvents: [SleepEvent]
    @Query(
        filter: #Predicate<SleepSession> { $0.isArchived == true },
        sort: \SleepSession.startTime,
        order: .reverse
    ) private var archivedSessions: [SleepSession]

    @State private var filter: EventFilter = .all
    @State private var selectedEvent: SleepEvent?
    @State private var searchQuery: String = ""

    enum EventFilter: Hashable, CaseIterable {
        case all, snore, sleepTalk, apnea, nightmare

        var label: String {
            switch self {
            case .all: "全部"
            case .snore: "打呼"
            case .sleepTalk: "梦话"
            case .apnea: "疑似呼吸暂停"
            case .nightmare: "夜惊"
            }
        }

        func matches(_ event: SleepEvent) -> Bool {
            switch self {
            case .all: return true
            case .snore: return event.type == .snore
            case .sleepTalk: return event.type == .sleepTalk
            case .apnea: return event.type == .suspectedApnea
            case .nightmare: return event.type == .nightmareSpike
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        searchBar
                        filterBar
                        wordCloudLink

                        if !archivedSessions.isEmpty {
                            sectionTitle("已归档的夜晚")
                            ForEach(archivedSessions) { s in
                                NavigationLink {
                                    SessionDetailView(session: s, fileStore: fileStore)
                                } label: {
                                    ArchivedSessionRow(session: s)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        sectionTitle(filteredEvents.isEmpty ? "事件" : "事件 (\(filteredEvents.count))")

                        if filteredEvents.isEmpty {
                            emptyEventsState
                        } else {
                            ForEach(filteredEvents) { e in
                                ArchiveEventRow(event: e, fileStore: fileStore)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedEvent = e }
                            }
                        }

                        Spacer().frame(height: 30)
                    }
                    .padding(.horizontal, Theme.padding)
                    .padding(.top, Theme.padding)
                }
            }
            .navigationTitle("档案")
            .sheet(item: $selectedEvent) { event in
                ArchiveEventDetailSheet(event: event, fileStore: fileStore)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Subviews

    /// Phase 3 P3.3：梦话关键词搜索
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textTertiary)
            TextField("搜索梦话转写", text: $searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EventFilter.allCases, id: \.self) { f in
                    Button {
                        filter = f
                    } label: {
                        Text(f.label)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(filter == f ? Theme.accent : Theme.surface)
                            .foregroundStyle(filter == f ? Color.black : Theme.textPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Phase 3 P3.7：跳转词云
    private var wordCloudLink: some View {
        NavigationLink {
            WordCloudView()
        } label: {
            HStack {
                Image(systemName: "cloud.fill")
                    .foregroundStyle(Theme.accentSecondary)
                Text("梦话词云")
                    .foregroundStyle(Theme.textPrimary)
                    .font(.subheadline).bold()
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.headline).foregroundStyle(Theme.textPrimary).padding(.top, 4)
    }

    private var emptyEventsState: some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var emptyMessage: String {
        if !searchQuery.isEmpty {
            return "没有匹配「\(searchQuery)」的梦话。"
        }
        if filter == .all {
            return "还没有记录到事件"
        }
        return "当前筛选下没有事件"
    }

    private var filteredEvents: [SleepEvent] {
        allEvents.filter { event in
            guard filter.matches(event) else { return false }
            // 搜索只作用在梦话 transcript 上
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                // 搜索模式下只看带转写的梦话事件
                guard event.type == .sleepTalk,
                      let t = event.transcript else { return false }
                return t.localizedCaseInsensitiveContains(query)
            }
            return true
        }
    }
}

// MARK: - Rows

private struct ArchivedSessionRow: View {
    let session: SleepSession

    var body: some View {
        HStack {
            Image(systemName: "archivebox.fill")
                .foregroundStyle(Theme.accentSecondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startTime, style: .date)
                    .font(.subheadline).bold()
                    .foregroundStyle(Theme.textPrimary)
                Text(TimeFormat.duration(session.durationSeconds) + " · 事件 \(session.events.count)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

private struct ArchiveEventRow: View {
    let event: SleepEvent
    let fileStore: AudioFileStore

    @StateObject private var player = SimpleAudioPlayer()
    @State private var isPlaying = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: eventIcon)
                .font(.system(size: 22))
                .foregroundStyle(eventColor)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(eventTypeLabel)
                        .font(.subheadline).bold()
                        .foregroundStyle(Theme.textPrimary)
                    Text(event.timestamp.formatted(date: .numeric, time: .standard))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if event.type == .sleepTalk, let t = event.transcript, !t.isEmpty {
                    Text(t)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(String(format: "时长 %.0fs · 置信 %.0f%%", event.duration, event.confidence * 100))
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer()

            if clipExists {
                Button {
                    togglePlay()
                } label: {
                    Image(systemName: isPlaying && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private var clipExists: Bool {
        guard let path = event.clipPath else { return false }
        return FileManager.default.fileExists(atPath: fileStore.url(fromRelativePath: path).path)
    }

    private func togglePlay() {
        guard let path = event.clipPath else { return }
        let url = fileStore.url(fromRelativePath: path)
        if isPlaying, player.isPlaying {
            player.pause()
        } else {
            isPlaying = true
            player.play(url: url)
        }
    }

    private var eventTypeLabel: String {
        switch event.type {
        case .snore: "打呼"
        case .sleepTalk: "梦话"
        case .suspectedApnea: "疑似呼吸暂停"
        case .nightmareSpike: "夜惊"
        }
    }

    private var eventIcon: String {
        switch event.type {
        case .snore: "waveform.path"
        case .sleepTalk: "bubble.left.and.bubble.right.fill"
        case .suspectedApnea: "lungs.fill"
        case .nightmareSpike: "exclamationmark.triangle.fill"
        }
    }

    private var eventColor: Color {
        switch event.type {
        case .snore: Color(red: 1.0, green: 0.4, blue: 0.4)
        case .sleepTalk: Color(red: 0.5, green: 0.85, blue: 0.55)
        case .suspectedApnea: Color(red: 1.0, green: 0.65, blue: 0.25)
        case .nightmareSpike: Color(red: 0.85, green: 0.45, blue: 0.95)
        }
    }
}

// MARK: - Detail sheet

private struct ArchiveEventDetailSheet: View {
    let event: SleepEvent
    let fileStore: AudioFileStore

    @StateObject private var player = SimpleAudioPlayer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerBlock
                        if event.type == .sleepTalk {
                            transcriptBlock
                        }
                        audioBlock
                        if let session = event.session {
                            NavigationLink {
                                SessionDetailView(session: session, fileStore: fileStore)
                            } label: {
                                HStack {
                                    Image(systemName: "arrowshape.turn.up.forward.fill")
                                    Text("跳转到整晚报告")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .padding(14)
                                .background(Theme.surface)
                                .foregroundStyle(Theme.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.padding)
                }
            }
            .navigationTitle(eventTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .onDisappear { player.stop() }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Text(String(format: "时长 %.0fs · 置信度 %.0f%%", event.duration, event.confidence * 100))
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var transcriptBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("转写")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if let t = event.transcript, !t.isEmpty {
                Text(t)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            } else {
                Text("（暂无转写，或识别为空）")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
        }
    }

    @ViewBuilder
    private var audioBlock: some View {
        if let path = event.clipPath,
           FileManager.default.fileExists(atPath: fileStore.url(fromRelativePath: path).path) {
            let url = fileStore.url(fromRelativePath: path)
            HStack(spacing: 14) {
                Button {
                    if player.isPlaying { player.pause() } else { player.play(url: url) }
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.isPlaying ? "播放中" : "点击播放片段")
                        .foregroundStyle(Theme.textPrimary)
                    Text(TimeFormat.duration(player.currentTime))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding()
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        } else {
            Text("音频片段已被清理或不存在。")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }

    private var eventTitle: String {
        switch event.type {
        case .snore: "打呼事件"
        case .sleepTalk: "梦话日记"
        case .suspectedApnea: "疑似呼吸暂停"
        case .nightmareSpike: "夜惊事件"
        }
    }
}
