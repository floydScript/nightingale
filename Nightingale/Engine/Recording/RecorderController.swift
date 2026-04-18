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
    private let transcriber: SleepTalkTranscriber

    private var currentSession: SleepSession?
    private var tickTimer: Timer?
    private var interruptionObserver: NSObjectProtocol?

    // 打呼识别链（Phase 1B）
    private var snoreDetector: SnoreDetector?
    private var snoreDebouncer = SnoreDebouncer()
    private var snoreTask: Task<Void, Never>?

    // 梦话识别链（Phase 2）
    private var talkDetector: SleepTalkDetector?
    private var talkDebouncer = SleepTalkDebouncer()
    private var talkTask: Task<Void, Never>?

    // 环境噪音监控（Phase 3 · P3.6）
    private var noiseMonitor: NoiseMonitor?

    init(
        modelContext: ModelContext,
        fileStore: AudioFileStore,
        permissions: PermissionManager,
        healthKit: HealthKitSync,
        clipExtractor: ClipExtractor,
        transcriber: SleepTalkTranscriber = SleepTalkTranscriber()
    ) {
        self.modelContext = modelContext
        self.fileStore = fileStore
        self.permissions = permissions
        self.healthKit = healthKit
        self.clipExtractor = clipExtractor
        self.transcriber = transcriber
        observeAudioInterruptions()
    }

    deinit {
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// 开始录音。未授权自动请求。会同时启动 SnoreDetector + SleepTalkDetector + NoiseMonitor。
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

            // 2. 基于 hardware format 构造两路检测器
            let format = recorder.inputFormat
            startSnoreDetector(format: format)
            startSleepTalkDetector(format: format)
            let noise = NoiseMonitor()
            self.noiseMonitor = noise

            // 3. 启动录音引擎，把 detector.feed 挂到 tap 回调；同一个 buffer fan-out 到三个 sink
            let snore = snoreDetector
            let talk = talkDetector
            let observer: AudioRecorder.BufferObserver? = { buffer, frame in
                snore?.feed(buffer, atFrame: frame)
                talk?.feed(buffer, atFrame: frame)
                noise.feed(buffer)
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
            teardownDetectors()
            state = .failed(message: "无法启动录音：\(error.localizedDescription)")
        }
    }

    /// 停止录音 + 触发异步后处理（HealthKit + 呼吸暂停检测 + 剪片段 + 梦话转写）。
    func stop() {
        guard case .recording = state else { return }
        state = .finalizing
        stopTick()

        // 停 snore detector 并 flush
        snoreDetector?.stop()
        if let last = snoreDebouncer.flush() {
            emitSnoreEvent(last)
        }
        // 停 sleep-talk detector 并 flush
        talkDetector?.stop()
        if let last = talkDebouncer.flush() {
            emitSleepTalkEvent(last)
        }
        // 抓 noise summary 前先停录音（buffer tap 里还会再 feed 一轮，没关系）
        let noiseSummary = noiseMonitor?.snapshot()
        noiseMonitor?.stop()
        teardownDetectors()

        do {
            try recorder.stop()
        } catch {
            NSLog("Stop error: \(error)")
        }

        if let session = currentSession {
            session.endTime = Date()
            if let summary = noiseSummary {
                session.ambientNoiseAverageDB = summary.averageDB
                session.ambientNoisePeakDB = summary.peakDB
            }
            do {
                try modelContext.save()
            } catch {
                NSLog("Failed to save session: \(error)")
            }

            // 异步后处理
            Task { [weak self] in
                await self?.postProcess(session: session)
            }
        }

        currentSession = nil
        state = .idle
    }

    // MARK: - Detector lifecycle

    private func startSnoreDetector(format: AVAudioFormat) {
        do {
            let d = SnoreDetector(format: format)
            try d.start()
            snoreDetector = d
            snoreDebouncer = SnoreDebouncer()
            snoreTask = Task { [weak self] in
                for await detection in d.detections {
                    await MainActor.run {
                        self?.handleSnoreDetection(detection)
                    }
                }
            }
        } catch {
            NSLog("SnoreDetector start failed (continuing without snore detection): \(error)")
            snoreDetector = nil
        }
    }

    private func startSleepTalkDetector(format: AVAudioFormat) {
        do {
            let d = SleepTalkDetector(format: format)
            try d.start()
            talkDetector = d
            talkDebouncer = SleepTalkDebouncer()
            talkTask = Task { [weak self] in
                for await detection in d.detections {
                    await MainActor.run {
                        self?.handleSleepTalkDetection(detection)
                    }
                }
            }
        } catch {
            NSLog("SleepTalkDetector start failed (continuing without sleep-talk detection): \(error)")
            talkDetector = nil
        }
    }

    private func teardownDetectors() {
        snoreTask?.cancel()
        snoreTask = nil
        snoreDetector = nil

        talkTask?.cancel()
        talkTask = nil
        talkDetector = nil

        noiseMonitor = nil
    }

    // MARK: - Event emission

    private func handleSnoreDetection(_ d: SnoreDetector.Detection) {
        if let merged = snoreDebouncer.feed(d) {
            emitSnoreEvent(merged)
        }
    }

    private func handleSleepTalkDetection(_ d: SleepTalkDetector.Detection) {
        if let merged = talkDebouncer.feed(d) {
            emitSleepTalkEvent(merged)
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

    private func emitSleepTalkEvent(_ merged: SleepTalkDebouncer.Merged) {
        guard let session = currentSession else { return }
        let timestamp = session.startTime.addingTimeInterval(merged.start)
        let event = SleepEvent(
            session: session,
            timestamp: timestamp,
            duration: merged.duration,
            type: .sleepTalk,
            confidence: merged.confidence
        )
        modelContext.insert(event)
        try? modelContext.save()
    }

    private func emitApneaEvent(_ candidate: ApneaDetector.Candidate, session: SleepSession) {
        let event = SleepEvent(
            session: session,
            timestamp: candidate.start,
            duration: candidate.duration,
            type: .suspectedApnea,
            confidence: candidate.confidence
        )
        modelContext.insert(event)
        try? modelContext.save()
    }

    private func emitNightmareEvent(_ candidate: NightmareDetector.Candidate, session: SleepSession) {
        let event = SleepEvent(
            session: session,
            timestamp: candidate.start,
            duration: candidate.duration,
            type: .nightmareSpike,
            confidence: candidate.confidence
        )
        modelContext.insert(event)
        try? modelContext.save()
    }

    // MARK: - Async post-processing

    private func postProcess(session: SleepSession) async {
        // 1. 拉 HealthKit（快）
        let hkGranted = await healthKit.requestAuthorization()
        if hkGranted {
            let end = session.endTime ?? Date()
            let samples = await healthKit.pullSamples(from: session.startTime, to: end)
            for s in samples {
                s.session = session
                modelContext.insert(s)
            }
            try? modelContext.save()
            NSLog("HealthKit pulled \(samples.count) samples")
        }

        // 2. 疑似呼吸暂停检测（需在有 SpO2 样本之后、在剪片段之前，
        //    这样新插入的 apnea 事件也能被 clip extraction 剪出片段）
        runApneaDetection(session: session)

        // 2.5 夜惊检测（Phase 3 · P3.5）。基于刚拉到的 HR + sleepStage，
        //     在 clip extraction 之前跑，让新事件也剪出片段。
        runNightmareDetection(session: session)

        // 3. 剪片段
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

        // 4. 梦话转写（逐个事件调用 Speech 框架，失败继续）
        let talkEvents = session.events.filter { $0.type == .sleepTalk && $0.transcript == nil }
        for event in talkEvents {
            guard let path = event.clipPath else { continue }
            let url = fileStore.url(fromRelativePath: path)
            let transcript = await transcriber.transcribe(url: url)
            if let t = transcript {
                event.transcript = t
                try? modelContext.save()
            }
        }
        NSLog("Sleep-talk transcription done for \(talkEvents.count) events")
    }

    /// 纯函数式呼吸暂停判定。输入是 events + SpO2 样本，输出新 SleepEvent。
    private func runApneaDetection(session: SleepSession) {
        let audioEvents: [ApneaDetector.AudioEvent] = session.events
            .filter { $0.type == .snore || $0.type == .sleepTalk }
            .map { .init(timestamp: $0.timestamp, duration: $0.duration) }

        let spo2Samples: [ApneaDetector.Spo2Sample] = session.sensorSamples
            .filter { $0.kind == .spo2 }
            .map { .init(timestamp: $0.timestamp, percent: $0.value) }

        guard !spo2Samples.isEmpty else {
            NSLog("Skipping apnea detection: no SpO2 samples")
            return
        }

        let detector = ApneaDetector()
        let input = ApneaDetector.Input(
            sessionStart: session.startTime,
            sessionEnd: session.endTime ?? Date(),
            audioEvents: audioEvents,
            spo2Samples: spo2Samples
        )
        let candidates = detector.detect(input)
        for c in candidates {
            emitApneaEvent(c, session: session)
        }
        NSLog("Apnea detection produced \(candidates.count) candidate(s)")
    }

    /// 纯函数式夜惊判定。输入是 HR + sleepStage 样本，输出新 SleepEvent(nightmareSpike)。
    private func runNightmareDetection(session: SleepSession) {
        let hrSamples = session.sensorSamples
            .filter { $0.kind == .heartRate }
            .map { NightmareDetector.HRSample(timestamp: $0.timestamp, bpm: $0.value) }

        let stageSegments = session.sensorSamples
            .filter { $0.kind == .sleepStage }
            .compactMap { s -> NightmareDetector.StageSegment? in
                guard let sv = s.stringValue else { return nil }
                let parts = sv.split(separator: "|").map(String.init)
                let stage = parts.first ?? "unknown"
                var end = s.timestamp.addingTimeInterval(60)
                if let endPart = parts.first(where: { $0.hasPrefix("end=") }),
                   let epoch = Double(endPart.dropFirst(4)) {
                    end = Date(timeIntervalSince1970: epoch)
                }
                return NightmareDetector.StageSegment(start: s.timestamp, end: end, stage: stage)
            }

        guard !hrSamples.isEmpty, !stageSegments.isEmpty else {
            NSLog("Skipping nightmare detection: missing HR or stage samples")
            return
        }

        let detector = NightmareDetector()
        let candidates = detector.detect(.init(hrSamples: hrSamples, stageSegments: stageSegments))
        for c in candidates {
            emitNightmareEvent(c, session: session)
        }
        NSLog("Nightmare detection produced \(candidates.count) candidate(s)")
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
