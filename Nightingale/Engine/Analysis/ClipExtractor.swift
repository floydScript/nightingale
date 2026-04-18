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
    private let minClipSeconds: Double = 0.1

    init(fileStore: AudioFileStore) {
        self.fileStore = fileStore
    }

    /// 从 fullAudioURL 剪出片段到 Clips/<eventID>.m4a。返回新片段 URL 或 nil（失败）。
    /// 时间窗口会被 clamp 到源音频实际时长内，避免产生 0-track 退化 clip。
    func extract(_ req: ClipRequest, from fullAudioURL: URL) async -> URL? {
        let asset = AVURLAsset(url: fullAudioURL)

        // 校验源音频有至少一条音轨
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard !tracks.isEmpty else {
                NSLog("ClipExtractor: source has no audio tracks: \(fullAudioURL.lastPathComponent)")
                return nil
            }
        } catch {
            NSLog("ClipExtractor: failed to load tracks from source: \(error)")
            return nil
        }

        // 用源时长 clamp 目标时间段
        let sourceDurationSec: Double
        do {
            let d = try await asset.load(.duration)
            sourceDurationSec = d.seconds.isFinite ? d.seconds : 0
        } catch {
            NSLog("ClipExtractor: failed to load duration: \(error)")
            return nil
        }

        let startSec = max(0, req.offsetFromStart - preRoll)
        let rawEndSec = req.offsetFromStart + req.duration + postRoll
        let endSec = min(rawEndSec, sourceDurationSec)
        let durSec = endSec - startSec

        guard durSec >= minClipSeconds else {
            NSLog("ClipExtractor: clip window too short (start=\(startSec) end=\(endSec) src=\(sourceDurationSec)) for \(req.eventID)")
            return nil
        }

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }

        let outURL = fileStore.clipURL(for: req.eventID)
        try? FileManager.default.removeItem(at: outURL)

        let start = CMTime(seconds: startSec, preferredTimescale: 600)
        let duration = CMTime(seconds: durSec, preferredTimescale: 600)
        export.timeRange = CMTimeRange(start: start, duration: duration)

        do {
            try await export.export(to: outURL, as: .m4a)
        } catch {
            NSLog("Clip export failed for \(req.eventID): \(error)")
            return nil
        }

        // 校验导出的 clip 确实包含音轨——防止导出成功但产物是 0-track 的边界情况
        let outAsset = AVURLAsset(url: outURL)
        do {
            let outTracks = try await outAsset.loadTracks(withMediaType: .audio)
            guard !outTracks.isEmpty else {
                NSLog("ClipExtractor: exported clip had 0 audio tracks, discarding: \(req.eventID)")
                try? FileManager.default.removeItem(at: outURL)
                return nil
            }
        } catch {
            NSLog("ClipExtractor: post-export track validation failed: \(error)")
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }

        return outURL
    }
}
