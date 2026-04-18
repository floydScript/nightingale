import Foundation
@preconcurrency import AVFoundation
@preconcurrency import SoundAnalysis

/// 从实时 PCM 流中识别 "speech" 类（梦话）。
///
/// 结构基本照抄 `SnoreDetector`，分类目标从 "snoring" 换成 "speech"，
/// 同样使用苹果预训练分类器 `SNClassifierIdentifier.version1`。
///
/// 用法：
/// 1. `init(format:)`（AudioRecorder 的 hardwareFormat）
/// 2. `start()` 绑定分类请求
/// 3. AudioRecorder tap 回调里调 `feed(buffer, atFrame:)`
/// 4. 通过 `detections` AsyncStream 消费检测结果
/// 5. 结束时 `stop()`
nonisolated final class SleepTalkDetector: @unchecked Sendable {

    struct Detection: Sendable {
        /// 相对于 SNAudioStreamAnalyzer 启动时的音频流内时间（秒）。
        let streamTime: TimeInterval
        let duration: TimeInterval
        let confidence: Double
    }

    private let analyzer: SNAudioStreamAnalyzer
    private let queue = DispatchQueue(label: "com.nightingale.sleeptalk-analysis", qos: .utility)
    private var request: SNClassifySoundRequest?
    private var observer: SpeechObserver?

    let detections: AsyncStream<Detection>
    private let continuation: AsyncStream<Detection>.Continuation

    init(format: AVAudioFormat) {
        self.analyzer = SNAudioStreamAnalyzer(format: format)
        var c: AsyncStream<Detection>.Continuation!
        self.detections = AsyncStream { c = $0 }
        self.continuation = c
    }

    func start() throws {
        let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
        req.overlapFactor = 0.5
        let obs = SpeechObserver(continuation: continuation)
        try analyzer.add(req, withObserver: obs)
        self.request = req
        self.observer = obs
    }

    /// 从 AudioRecorder 的 tap 回调里调用，线程安全：内部派发到串行 queue。
    func feed(_ buffer: AVAudioPCMBuffer, atFrame frame: AVAudioFramePosition) {
        let analyzer = self.analyzer
        queue.async {
            analyzer.analyze(buffer, atAudioFramePosition: frame)
        }
    }

    func stop() {
        analyzer.removeAllRequests()
        continuation.finish()
    }
}

private nonisolated final class SpeechObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    let continuation: AsyncStream<SleepTalkDetector.Detection>.Continuation
    /// 置信度阈值。清醒朗读几秒钟常在 0.5-0.7 之间，0.7 过高；降到 0.5。
    let emitThreshold: Double = 0.5
    /// 低于 emit 阈值但 ≥ debugThreshold 的分类也会 NSLog，方便排查"为什么没识别"。
    let debugLogThreshold: Double = 0.3
    /// 同时监听的类——speech 是主力，whispering / chatter 作为兜底（睡觉时低声说梦话常命中 whispering）。
    static let candidateIdentifiers: [String] = ["speech", "whispering", "chatter", "singing"]

    init(continuation: AsyncStream<SleepTalkDetector.Detection>.Continuation) {
        self.continuation = continuation
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }

        // 记录所有候选类的置信度（≥ 0.3）——Xcode console 里能看
        var best: (identifier: String, confidence: Double)? = nil
        for ident in Self.candidateIdentifiers {
            if let c = result.classification(forIdentifier: ident) {
                if c.confidence >= debugLogThreshold {
                    NSLog("SleepTalk[t=%.1f]: %@=%.2f", result.timeRange.start.seconds, ident, c.confidence)
                }
                if best == nil || c.confidence > best!.confidence {
                    best = (ident, c.confidence)
                }
            }
        }

        guard let best, best.confidence >= emitThreshold else { return }

        let d = SleepTalkDetector.Detection(
            streamTime: result.timeRange.start.seconds,
            duration: result.timeRange.duration.seconds,
            confidence: best.confidence
        )
        continuation.yield(d)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        NSLog("SleepTalk SNRequest failed: \(error)")
    }

    func requestDidComplete(_ request: SNRequest) {}
}
