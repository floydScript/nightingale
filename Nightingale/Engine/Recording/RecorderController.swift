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
    private let healthKit: HealthKitSync
    private let clipExtractor: ClipExtractor

    private var currentSession: SleepSession?
    private var tickTimer: Timer?
    private var interruptionObserver: NSObjectProtocol?

    // 打呼识别链
    private var detector: SnoreDetector?
    private var debouncer = SnoreDebouncer()
    private var detectionTask: Task<Void, Never>?

    init(
        modelContext: ModelContext,
        fileStore: AudioFileStore,
        permissions: PermissionManager,
        healthKit: HealthKitSync,
        clipExtractor: ClipExtractor
    ) {
        self.modelContext = modelContext
        self.fileStore = fileStore
        self.permissions = permissions
        self.healthKit = healthKit
        self.clipExtractor = clipExtractor
        observeAudioInterruptions()
    }

    deinit {
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// 开始录音。未授权自动请求。会同时启动 SnoreDetector。
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
            // 1. 先配置 session，让 recorder.inputFormat 可读
            try recorder.setupSession()

            // 2. 基于 hardware format 构造并启动 SnoreDetector
            let format = recorder.inputFormat
            let d = SnoreDetector(format: format)
            do {
                try d.start()
                detector = d
                debouncer = SnoreDebouncer()
                detectionTask = Task { [weak self] in
                    for await detection in d.detections {
                        await MainActor.run {
                            self?.handleDetection(detection)
                        }
                    }
                }
            } catch {
                NSLog("SnoreDetector start failed (continuing recording without detection): \(error)")
                detector = nil
            }

            // 3. 启动录音引擎，把 detector.feed 挂到 tap 回调
            let observer: AudioRecorder.BufferObserver? = if let det = detector {
                { buffer, frame in det.feed(buffer, atFrame: frame) }
            } else {
                nil
            }
            try recorder.start(writingTo: url, bufferObserver: observer)
            session.fullAudioPath = fileStore.relativePath(for: url)
            try modelContext.save()
            currentSession = session

            state = .recording(startedAt: session.startTime)
            startTick()
        } catch {
            modelContext.delete(session)
            try? modelContext.save()
            detector?.stop()
            detectionTask?.cancel()
            detector = nil
            detectionTask = nil
            state = .failed(message: "无法启动录音：\(error.localizedDescription)")
        }
    }

    /// 停止录音 + 触发异步后处理（剪片段 + 拉 HealthKit）。
    func stop() {
        guard case .recording = state else { return }
        state = .finalizing
        stopTick()

        // 停 detector 并 flush 最后一个事件
        detector?.stop()
        if let last = debouncer.flush() {
            emitSnoreEvent(last)
        }
        detectionTask?.cancel()
        detectionTask = nil
        detector = nil

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

            // 异步后处理：先拉 HealthKit（快），再剪片段（慢）
            Task { [weak self] in
                await self?.postProcess(session: session)
            }
        }

        currentSession = nil
        state = .idle
    }

    // MARK: - 事件处理

    private func handleDetection(_ d: SnoreDetector.Detection) {
        if let merged = debouncer.feed(d) {
            emitSnoreEvent(merged)
        }
    }

    private func emitSnoreEvent(_ merged: SnoreDebouncer.Merged) {
        guard let session = currentSession else { return }
        let timestamp = session.startTime.addingTimeInterval(merged.start)
        let event = SleepEvent(
            session: session,
            timestamp: timestamp,
            duration: merged.duration,
            type: .snore,
            confidence: merged.confidence
        )
        modelContext.insert(event)
        try? modelContext.save()
    }

    // MARK: - 异步后处理

    private func postProcess(session: SleepSession) async {
        // 1. HealthKit
        let granted = await healthKit.requestAuthorization()
        if granted {
            let end = session.endTime ?? Date()
            let samples = await healthKit.pullSamples(from: session.startTime, to: end)
            for s in samples {
                s.session = session
                modelContext.insert(s)
            }
            try? modelContext.save()
            NSLog("HealthKit pulled \(samples.count) samples")
        }

        // 2. 剪片段
        guard let relPath = session.fullAudioPath else { return }
        let fullURL = fileStore.url(fromRelativePath: relPath)
        let events = session.events
        for event in events where event.clipPath == nil {
            let offsetFromStart = event.timestamp.timeIntervalSince(session.startTime)
            let req = ClipExtractor.ClipRequest(
                eventID: event.id,
                offsetFromStart: offsetFromStart,
                duration: event.duration
            )
            if let clipURL = await clipExtractor.extract(req, from: fullURL) {
                event.clipPath = fileStore.relativePath(for: clipURL)
                try? modelContext.save()
            }
        }
        NSLog("Clip extraction done for \(events.count) events")
    }

    // MARK: - Tick / interruption

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
