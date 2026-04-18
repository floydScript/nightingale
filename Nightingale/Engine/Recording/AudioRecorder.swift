import Foundation
import AVFoundation

/// 低层录音引擎：把 AVAudioEngine 的输入流写入 AAC m4a 文件。
/// 单实例、外部保证串行调用。
/// 必须 `nonisolated`——installTap 的回调运行在音频渲染线程，不能走 MainActor。
nonisolated final class AudioRecorder {

    enum RecorderError: Error {
        case sessionActivationFailed(Error)
        case fileCreationFailed(Error)
        case engineStartFailed(Error)
        case alreadyRunning
        case notRunning
    }

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var _isRunning = false
    private let lock = NSLock()

    /// 配置并启动录音，写入 outputURL。
    /// 采样率跟随硬件，AAC 32 kbps 单声道 16 kHz 目标文件。
    func start(writingTo outputURL: URL) throws {
        lock.lock(); defer { lock.unlock() }
        guard !_isRunning else { throw RecorderError.alreadyRunning }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch {
            throw RecorderError.sessionActivationFailed(error)
        }

        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)

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

        input.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self, let file = self.audioFile else { return }
            do {
                try file.write(from: buffer)
            } catch {
                NSLog("AudioRecorder write failed: \(error)")
            }
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

    /// 停止录音并 flush 文件。安全重复调用。
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
