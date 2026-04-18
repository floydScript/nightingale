import Foundation
import AVFoundation

/// 低层录音引擎：把 AVAudioEngine 输入流写入 AAC m4a。
/// `nonisolated` + `@unchecked Sendable`——installTap 的回调在音频渲染线程运行。
nonisolated final class AudioRecorder: @unchecked Sendable {

    enum RecorderError: Error {
        case sessionActivationFailed(Error)
        case fileCreationFailed(Error)
        case engineStartFailed(Error)
        case alreadyRunning
        case notRunning
    }

    /// tap 回调时额外透出原始 buffer 给外部（例如 SoundAnalysis 分析器）。
    /// AVAudioPCMBuffer 不是严格 Sendable，我们信任调用方安全使用。
    typealias BufferObserver = @Sendable (AVAudioPCMBuffer, AVAudioFramePosition) -> Void

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var _isRunning = false
    private let lock = NSLock()

    /// 配置 AVAudioSession 为 .record。必须在 start() 之前调用；中间可以读取 `inputFormat`。
    func setupSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch {
            throw RecorderError.sessionActivationFailed(error)
        }
    }

    /// 当前 input 的 hardware format。setupSession 之后读取；供 SnoreDetector 等初始化用。
    var inputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func start(
        writingTo outputURL: URL,
        bufferObserver: BufferObserver? = nil
    ) throws {
        lock.lock(); defer { lock.unlock() }
        guard !_isRunning else { throw RecorderError.alreadyRunning }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
        } catch {
            throw RecorderError.fileCreationFailed(error)
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self, bufferObserver] buffer, when in
            guard let self, let file = self.audioFile else { return }
            do {
                try file.write(from: buffer)
            } catch {
                NSLog("AudioRecorder write failed: \(error)")
            }
            bufferObserver?(buffer, when.sampleTime)
        }

        do {
            try engine.start()
            _isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            audioFile = nil
            throw RecorderError.engineStartFailed(error)
        }
    }

    func stop() throws {
        lock.lock(); defer { lock.unlock() }
        guard _isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        _isRunning = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    var running: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRunning
    }
}
