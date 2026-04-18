import SwiftUI
import SwiftData
import AVFoundation
import Combine

struct SessionDetailView: View {
    let session: SleepSession
    let fileStore: AudioFileStore

    @Environment(\.modelContext) private var modelContext
    @StateObject private var player = SimpleAudioPlayer()
    /// 正在播放的事件 ID；nil 表示播整夜音频或未在播。
    @State private var selectedEventID: UUID?
    @State private var isPlayingFullNight = false

    // Phase 2 晨间打卡的本地编辑缓冲，避免每输入一个字都写 SwiftData
    @State private var moodDraft: String = ""
    @State private var noteDraft: String = ""
    // 控制 onChange 初始化时不触发保存
    @State private var didHydrate = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    morningCheckIn
                    metricsGrid

                    sectionTitle("综合时间轴")
                    OverlayTimelineChart(session: session)

                    sectionTitle("睡眠分期")
                    SleepStageChart(session: session)

                    sectionTitle("心率")
                    HeartRateChart(session: session)

                    sectionTitle("血氧")
                    SpO2Chart(session: session)

                    sectionTitle("打呼时间轴")
                    SnoreTimelineChart(session: session)

                    sectionTitle("事件列表")
                    eventList

                    sectionTitle("整夜音频")
                    fullNightPlayer

                    archiveButton

                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, Theme.padding)
                .padding(.top, Theme.padding)
            }
        }
        .navigationTitle(session.startTime.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: hydrateDrafts)
        .onDisappear { player.stop() }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.startTime, style: .date)
                .font(.title3).bold()
                .foregroundStyle(Theme.textPrimary)
            Text(TimeFormat.duration(session.durationSeconds))
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
        }
    }

    // MARK: Phase 2 · 晨间打卡

    private static let moodOptions: [String] = ["😴", "😊", "😐", "😫", "🤒", "🎉"]

    private var morningCheckIn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("晨间打卡")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.moodOptions, id: \.self) { emoji in
                        Button {
                            moodDraft = (moodDraft == emoji) ? "" : emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: 30))
                                .padding(10)
                                .frame(minWidth: 54, minHeight: 54)
                                .background(moodDraft == emoji ? Theme.accent.opacity(0.25) : Theme.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(moodDraft == emoji ? Theme.accent : Color.clear, lineWidth: 2)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField("一句话", text: $noteDraft, axis: .vertical)
                .lineLimit(1...3)
                .padding(12)
                .background(Theme.surfaceElevated)
                .foregroundStyle(Theme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .submitLabel(.done)
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .onChange(of: moodDraft) { _, _ in persistMorningInputsIfHydrated() }
        .onChange(of: noteDraft) { _, _ in persistMorningInputsIfHydrated() }
    }

    private func hydrateDrafts() {
        moodDraft = session.morningMood ?? ""
        noteDraft = session.morningNote ?? ""
        didHydrate = true
    }

    private func persistMorningInputsIfHydrated() {
        guard didHydrate else { return }
        let newMood: String? = moodDraft.isEmpty ? nil : moodDraft
        let newNote: String? = noteDraft.isEmpty ? nil : noteDraft
        if session.morningMood != newMood {
            session.morningMood = newMood
        }
        if session.morningNote != newNote {
            session.morningNote = newNote
        }
        try? modelContext.save()
    }

    // MARK: 指标 / 图表

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricCard(label: "时长", value: TimeFormat.duration(session.durationSeconds))
            metricCard(label: "打呼次数", value: "\(session.snoreCount)")
            metricCard(
                label: "平均心率",
                value: session.averageHeartRate.map { String(format: "%.0f BPM", $0) } ?? "—"
            )
            metricCard(
                label: "最低 SpO₂",
                value: session.minSpO2.map { String(format: "%.1f%%", $0) } ?? "—"
            )
        }
    }

    private func metricCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            Text(value).font(.title3).bold().foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            .padding(.top, 6)
    }

    @ViewBuilder
    private var eventList: some View {
        let events = session.events.sorted { $0.timestamp > $1.timestamp }
        if events.isEmpty {
            Text("本晚未检测到事件。")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 8) {
                ForEach(events) { event in
                    EventRow(
                        event: event,
                        isPlaying: player.isPlaying && selectedEventID == event.id,
                        clipAvailable: clipExists(for: event),
                        onTap: { handleEventTap(event) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var fullNightPlayer: some View {
        if let relative = session.fullAudioPath,
           FileManager.default.fileExists(atPath: fileStore.url(fromRelativePath: relative).path) {
            HStack(spacing: 14) {
                Button {
                    handleFullNightTap(url: fileStore.url(fromRelativePath: relative))
                } label: {
                    Image(systemName: isPlayingFullNight && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isPlayingFullNight && player.isPlaying ? "播放中" : "点击播放整夜")
                        .foregroundStyle(Theme.textPrimary)
                    Text(isPlayingFullNight ? TimeFormat.duration(player.currentTime) : "—")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding()
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        } else {
            Text("整夜音频已被清理或尚未保存完成。")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }

    // MARK: 归档按钮（Phase 2）

    private var archiveButton: some View {
        Button {
            session.isArchived.toggle()
            try? modelContext.save()
        } label: {
            HStack {
                Image(systemName: session.isArchived ? "archivebox.fill" : "archivebox")
                Text(session.isArchived ? "已归档（点击取消）" : "归档这一晚")
                    .bold()
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(session.isArchived ? Theme.accentSecondary.opacity(0.25) : Theme.surface)
            .foregroundStyle(session.isArchived ? Theme.accentSecondary : Theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tap handlers

    private func handleEventTap(_ event: SleepEvent) {
        guard let path = event.clipPath else { return }
        let url = fileStore.url(fromRelativePath: path)
        if selectedEventID == event.id, player.isPlaying {
            player.pause()
        } else {
            selectedEventID = event.id
            isPlayingFullNight = false
            player.play(url: url)
        }
    }

    private func handleFullNightTap(url: URL) {
        if isPlayingFullNight, player.isPlaying {
            player.pause()
        } else {
            selectedEventID = nil
            isPlayingFullNight = true
            player.play(url: url)
        }
    }

    private func clipExists(for event: SleepEvent) -> Bool {
        guard let path = event.clipPath else { return false }
        return FileManager.default.fileExists(atPath: fileStore.url(fromRelativePath: path).path)
    }
}

private struct EventRow: View {
    let event: SleepEvent
    let isPlaying: Bool
    let clipAvailable: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isPlaying ? "pause.circle.fill" : (clipAvailable ? "play.circle.fill" : "waveform"))
                .font(.system(size: 28))
                .foregroundStyle(clipAvailable ? Theme.accent : Theme.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(eventLabel)
                    .foregroundStyle(Theme.textPrimary)
                    .font(.subheadline).bold()
                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if event.type == .sleepTalk, let t = event.transcript, !t.isEmpty {
                    Text(t)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            Text(String(format: "%.0fs · %.0f%%", event.duration, event.confidence * 100))
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .opacity(clipAvailable ? 1 : 0.55)
    }

    private var eventLabel: String {
        switch event.type {
        case .snore: "打呼"
        case .sleepTalk: "梦话"
        case .suspectedApnea: "疑似呼吸暂停"
        case .nightmareSpike: "夜惊"
        }
    }
}

@MainActor
final class SimpleAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0

    private var avPlayer: AVAudioPlayer?
    private var timer: Timer?

    func play(url: URL) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            avPlayer = try AVAudioPlayer(contentsOf: url)
            avPlayer?.delegate = self
            avPlayer?.prepareToPlay()
            avPlayer?.play()
            isPlaying = true
            startTimer()
        } catch {
            NSLog("Playback failed: \(error)")
        }
    }

    func pause() {
        avPlayer?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        avPlayer?.stop()
        avPlayer = nil
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.currentTime = self?.avPlayer?.currentTime ?? 0
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopTimer()
        }
    }
}
