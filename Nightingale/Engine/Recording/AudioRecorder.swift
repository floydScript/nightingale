import Foundation
import AVFoundation

/// 低层录音引擎：把 AVAudioEngine 输入流写入 AAC m4a。
/// `nonisolated` + `@unchecked Sendable`——installTap 的回调在音频渲染线程运行。
///
/// 核心设计：
/// 1. 硬件 tap 走硬件 format（通常 48kHz），**通过 AVAudioConverter 降到 16kHz**
///    再写入文件。之前直接把硬件 buffer 写进 16kHz-header 的文件，导致播放被拉伸。
/// 2. 传给 bufferObserver 的 frame position 是我们自己维护的 **从 0 开始的单调计数**，
///    不是 `AVAudioTime.sampleTime`——后者是 host 时钟的绝对 sample 值，常是几百万/
///    几亿的大数，直接喂 SoundAnalysis 会让 SNClassificationResult.timeRange 算出
///    完全错位的时间戳（几千秒量级），事件时间全错。
nonisolated final class AudioRecorder: @unchecked Sendable {

    enum RecorderError: Error {
        case sessionActivationFailed(Error)
        case fileCreationFailed(Error)
        case engineStartFailed(Error)
        case converterSetupFailed
        case alreadyRunning
        case notRunning
    }

    /// tap 回调时额外透出原始 buffer 给外部（SoundAnalysis 等）。
    /// 第二个参数是**从本次录音开始的单调帧计数**，不是 AVAudioTime.sampleTime。
    typealias BufferObserver = @Sendable (AVAudioPCMBuffer, AVAudioFramePosition) -> Void

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var _isRunning = false
    private let lock = NSLock()

    /// 本次录音累计 tap 回调接收到的帧数。每次 start() 会归零。
    /// 只有 tap 回调（串行）会写它，`nonisolated(unsafe)` 在此 OK。
    nonisolated(unsafe) private var framesProcessed: AVAudioFramePosition = 0

    /// 配置 AVAudioSession 为 .record。必须在 start() 之前调用。
    func setupSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch {
            throw RecorderError.sessionActivationFailed(error)
        }
    }

    /// 当前 input 的 hardware format。setupSession 之后读取。
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
        let hardwareFormat = input.outputFormat(forBus: 0)

        // 目标格式：16kHz mono PCM Float32
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw RecorderError.converterSetupFailed
        }

        guard let conv = AVAudioConverter(from: hardwareFormat, to: target) else {
            throw RecorderError.converterSetupFailed
        }

        self.targetFormat = target
        self.converter = conv

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

        // 归零帧计数器：每次录音从 0 开始
        framesProcessed = 0

        input.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self, bufferObserver] buffer, _ in
            guard let self else { return }

            // 用本次录音内的单调帧计数作为事件时间锚点。
            // （tap 回调被 AVAudioEngine 串行化，此处读-改-写无需额外锁。）
            let frame = self.framesProcessed
            self.framesProcessed = frame &+ AVAudioFramePosition(buffer.frameLength)

            // 1. 原始硬件 buffer 透传给观察者
            bufferObserver?(buffer, frame)

            // 2. 降采样到 16kHz mono 再写文件
            guard let file = self.audioFile,
                  let converter = self.converter,
                  let target = self.targetFormat else { return }

            let ratio = target.sampleRate / buffer.format.sampleRate
            let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: frameCapacity) else { return }

            var providedInput = false
            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                if providedInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                providedInput = true
                outStatus.pointee = .haveData
                return buffer
            }

            switch status {
            case .haveData, .endOfStream:
                do {
                    try file.write(from: outBuffer)
                } catch {
                    NSLog("AudioRecorder file.write failed: \(error)")
                }
            case .error:
                NSLog("AudioRecorder converter failed: \(error?.localizedDescription ?? "unknown")")
            case .inputRanDry:
                break
            @unknown default:
                break
            }
        }

        do {
            try engine.start()
            _isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            audioFile = nil
            converter = nil
            targetFormat = nil
            throw RecorderError.engineStartFailed(error)
        }
    }

    func stop() throws {
        lock.lock(); defer { lock.unlock() }
        guard _isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        converter = nil
        targetFormat = nil
        _isRunning = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    var running: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRunning
    }
}
