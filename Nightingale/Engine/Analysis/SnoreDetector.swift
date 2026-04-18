import Foundation
@preconcurrency import AVFoundation
@preconcurrency import SoundAnalysis

/// 从实时 PCM 流中识别 "snoring" 类。
///
/// 用法：
/// 1. `init(format:)`（AudioRecorder 的 hardwareFormat）
/// 2. `start()` 绑定分类请求
/// 3. AudioRecorder tap 回调里调 `feed(buffer, atFrame:)`
/// 4. 通过 `detections` AsyncStream 消费检测结果
/// 5. 结束时 `stop()`
nonisolated final class SnoreDetector: @unchecked Sendable {

    struct Detection: Sendable {
        /// 相对于 SNAudioStreamAnalyzer 启动时的音频流内时间（秒）。
        let streamTime: TimeInterval
        let duration: TimeInterval
        let confidence: Double
    }

    private let analyzer: SNAudioStreamAnalyzer
    private let queue = DispatchQueue(label: "com.nightingale.snore-analysis", qos: .utility)
    private var request: SNClassifySoundRequest?
    private var observer: ClassificationObserver?

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
        let obs = ClassificationObserver(continuation: continuation)
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

private nonisolated final class ClassificationObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    let continuation: AsyncStream<SnoreDetector.Detection>.Continuation
    let threshold: Double = 0.7

    init(continuation: AsyncStream<SnoreDetector.Detection>.Continuation) {
        self.continuation = continuation
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        if let c = result.classification(forIdentifier: "snoring"), c.confidence >= threshold {
            let d = SnoreDetector.Detection(
                streamTime: result.timeRange.start.seconds,
                duration: result.timeRange.duration.seconds,
                confidence: c.confidence
            )
            continuation.yield(d)
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        NSLog("SNRequest failed: \(error)")
    }

    func requestDidComplete(_ request: SNRequest) {}
}
