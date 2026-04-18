import Foundation
@preconcurrency import AVFoundation

/// 环境噪音监控（Phase 3 · P3.6）。
///
/// 设计：
/// - 和 SnoreDetector / SleepTalkDetector 并列，挂在 AudioRecorder 的 buffer fan-out
/// - 每喂一个 buffer 计算其 RMS → 转成分贝（相对满量程）→ 累加到 running avg/peak
/// - 录完一晚只返回一个 summary（average + peak），不产 per-event 数据
/// - 轻量：不做 FFT、不做 SoundAnalysis，只算 RMS（每 buffer 约 4096 samples）
///
/// 不是严格的声压级（SPL）——iPhone 的输入 RMS 到 SPL 需要标定，这里仅做"相对响度"
/// 指标。用户在图表里看到的是 "整夜相对平均 dB"，阈值和判定在 UI 层用经验值（如 >50）。
nonisolated final class NoiseMonitor: @unchecked Sendable {

    struct Summary: Sendable, Equatable {
        /// 整夜 RMS → dBFS 的平均（通常为负值，越接近 0 越响）。
        let averageDB: Double
        /// 整夜 RMS → dBFS 的峰值。
        let peakDB: Double
        /// 参与平均的 buffer 数量。
        let sampleCount: Int

        /// 便于 UI 显示成"相对 dB"数值（反转取正数）。
        var relativeAverage: Double { 100.0 + averageDB }
        var relativePeak: Double { 100.0 + peakDB }
    }

    private let lock = NSLock()
    private var runningSum: Double = 0
    private var peak: Double = -.infinity
    private var count: Int = 0

    init() {}

    /// 从 AudioRecorder 的 tap 回调调用。线程安全（内部锁）。
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)

        // 计算所有通道的平均 RMS
        var sumSquares: Double = 0
        for ch in 0..<channels {
            let ptr = channelData[ch]
            for i in 0..<frames {
                let v = Double(ptr[i])
                sumSquares += v * v
            }
        }
        let totalSamples = frames * max(1, channels)
        guard totalSamples > 0 else { return }
        let rms = sqrt(sumSquares / Double(totalSamples))
        // RMS → dBFS：20 * log10(rms)。rms=1 → 0 dB（满幅），rms=0.01 → -40 dB
        let db: Double
        if rms < 1e-8 {
            db = -160
        } else {
            db = 20 * log10(rms)
        }

        lock.lock()
        runningSum += db
        if db > peak { peak = db }
        count += 1
        lock.unlock()
    }

    /// 读取当前统计快照。录音中或结束后均可。无样本时返回 nil。
    func snapshot() -> Summary? {
        lock.lock(); defer { lock.unlock() }
        guard count > 0 else { return nil }
        return Summary(
            averageDB: runningSum / Double(count),
            peakDB: peak == -.infinity ? -160 : peak,
            sampleCount: count
        )
    }

    /// stop() 只清标志位，允许下次复用。当前实现没有额外资源要释放。
    func stop() {}

    // MARK: - UI 阈值

    /// "高噪音"阈值（相对 dB，越高越响）。>50 提示用户"外界干扰较大"。
    /// 这对应 dBFS ≈ -50，iPhone 夜间内置麦在安静卧室通常 20-35 之间。
    static let highNoiseRelativeThreshold: Double = 50
}
