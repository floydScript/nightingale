import Foundation
import SwiftData
import AVFoundation
import Combine

@MainActor
final class RecorderController: ObservableObject {

    @Published private(set) var state: RecorderState = .idle

    private let recorder = AudioRecorder()
    private let fileStore: AudioFileStore
    private let modelContext: ModelContext
    private let permissions: PermissionManager

    private var currentSession: SleepSession?
    private var tickTimer: Timer?
    private var interruptionObserver: NSObjectProtocol?

    init(
        modelContext: ModelContext,
        fileStore: AudioFileStore,
        permissions: PermissionManager
    ) {
        self.modelContext = modelContext
        self.fileStore = fileStore
        self.permissions = permissions
        observeAudioInterruptions()
    }

    deinit {
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// 入口：开始录音。未授权会自动请求。
    func start() async {
        guard case .idle = state else { return }

        let granted = await permissions.requestMicrophone()
        guard granted else {
            state = .failed(message: "未授权麦克风，请到系统设置 → Nightingale → 麦克风打开权限。")
            return
        }

        let session = SleepSession(startTime: Date())
        modelContext.insert(session)

        let url = fileStore.fullRecordingURL(for: session.id)

        do {
            try recorder.start(writingTo: url)
            session.fullAudioPath = fileStore.relativePath(for: url)
            try modelContext.save()
            currentSession = session
            state = .recording(startedAt: session.startTime)
            startTick()
        } catch {
            modelContext.delete(session)
            try? modelContext.save()
            state = .failed(message: "无法启动录音：\(error.localizedDescription)")
        }
    }

    /// 入口：停止录音并保存。
    func stop() {
        guard case .recording = state else { return }
        state = .finalizing
        stopTick()

        do {
            try recorder.stop()
        } catch {
            NSLog("Stop error: \(error)")
        }

        if let session = currentSession {
            session.endTime = Date()
            do {
                try modelContext.save()
            } catch {
                NSLog("Failed to save session: \(error)")
            }
        }

        currentSession = nil
        state = .idle
    }

    private func startTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self, case .recording(let start) = self.state else { return }
                self.state = .recording(startedAt: start)
            }
        }
    }

    private func stopTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func observeAudioInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { notification in
            // Extract Sendable raw value before hopping to MainActor, since Notification itself is not Sendable.
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleInterruption(typeRaw: typeRaw)
            }
        }
    }

    private func handleInterruption(typeRaw: UInt?) {
        guard let typeRaw,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            NSLog("Audio interrupted")
        case .ended:
            if case .recording = state {
                NSLog("Interruption ended; session continuing")
            }
        @unknown default:
            break
        }
    }
}
