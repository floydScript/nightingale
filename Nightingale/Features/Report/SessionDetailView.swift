import SwiftUI
import SwiftData
import AVFoundation
import Combine

struct SessionDetailView: View {

    let session: SleepSession
    let fileStore: AudioFileStore

    @StateObject private var player = SimpleAudioPlayer()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    metaCard
                    playerCard
                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, Theme.padding)
                .padding(.top, Theme.padding)
            }
        }
        .navigationTitle(session.startTime.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }

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

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(label: "开始", value: session.startTime.formatted(date: .omitted, time: .shortened))
            row(label: "结束", value: session.endTime?.formatted(date: .omitted, time: .shortened) ?? "—")
            row(label: "存档", value: session.isArchived ? "已归档" : "7 天内自动清理整夜音频")
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    @ViewBuilder
    private var playerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("整夜音频").font(.headline).foregroundStyle(Theme.textPrimary)

            if let relative = session.fullAudioPath,
               FileManager.default.fileExists(atPath: fileStore.url(fromRelativePath: relative).path) {
                HStack(spacing: 14) {
                    Button {
                        if player.isPlaying { player.pause() }
                        else { player.play(url: fileStore.url(fromRelativePath: relative)) }
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.isPlaying ? "播放中" : "点击播放")
                            .foregroundStyle(Theme.textPrimary)
                        Text(TimeFormat.duration(player.currentTime))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
            } else {
                Text("整夜音频已被清理或尚未保存完成。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary).font(.system(.body, design: .monospaced))
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
