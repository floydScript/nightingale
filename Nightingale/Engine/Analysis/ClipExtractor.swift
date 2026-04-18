import Foundation
import AVFoundation

/// 录音结束后，为每个事件从整夜 m4a 剪一段 (preRoll + event + postRoll) 独立 m4a。
nonisolated final class ClipExtractor: @unchecked Sendable {

    struct ClipRequest: Sendable {
        let eventID: UUID
        /// 事件起点相对录制起点的偏移（秒）。
        let offsetFromStart: TimeInterval
        let duration: TimeInterval
    }

    private let fileStore: AudioFileStore
    private let preRoll: Double = 15
    private let postRoll: Double = 15

    init(fileStore: AudioFileStore) {
        self.fileStore = fileStore
    }

    /// 从 fullAudioURL 剪出片段到 Clips/<eventID>.m4a。返回新片段 URL 或 nil（失败）。
    func extract(_ req: ClipRequest, from fullAudioURL: URL) async -> URL? {
        let asset = AVURLAsset(url: fullAudioURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        let outURL = fileStore.clipURL(for: req.eventID)
        try? FileManager.default.removeItem(at: outURL)

        let startSec = max(0, req.offsetFromStart - preRoll)
        let durSec = req.duration + preRoll + postRoll
        let start = CMTime(seconds: startSec, preferredTimescale: 600)
        let duration = CMTime(seconds: durSec, preferredTimescale: 600)
        export.timeRange = CMTimeRange(start: start, duration: duration)

        do {
            try await export.export(to: outURL, as: .m4a)
            return outURL
        } catch {
            NSLog("Clip export failed for \(req.eventID): \(error)")
            return nil
        }
    }
}
