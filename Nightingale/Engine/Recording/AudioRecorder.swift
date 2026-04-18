import Foundation
import AVFoundation

/// 低层录音引擎：把 AVAudioEngine 输入流写入 AAC m4a。
/// `nonisolated` + `@unchecked Sendable`——installTap 的回调在音频渲染线程运行。
///
/// 核心设计：硬件 tap 走硬件 format（通常 48kHz），**通过 AVAudioConverter 降到 16kHz**
/// 再写入文件。之前直接把硬件 buffer 写进 16kHz-header 的文件，导致播放时被拉伸。
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
    /// 注意：这里给出的是 **硬件 format 的 buffer**，不是文件里存的 16kHz 版本。
    typealias BufferObserver = @Sendable (AVAudioPCMBuffer, AVAudioFramePosition) -> Void

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var _isRunning = false
    private let lock = NSLock()

    /// 配置 AVAudioSession 为 .record。必须在 start() 之前调用；中间可读 `inputFormat`。
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
        let hardwareFormat = input.outputFormat(forBus: 0)

        // 目标格式：16kHz mono PCM Float32。AVAudioFile 写入时会进一步 AAC 压缩。
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

        input.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self, bufferObserver] buffer, when in
            guard let self else { return }

            // 1. 原始硬件 buffer 透传给观察者（SoundAnalysis、NoiseMonitor 等）
            //    SNAudioStreamAnalyzer 自己会 resample，无需我们干预
            bufferObserver?(buffer, when.sampleTime)

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
