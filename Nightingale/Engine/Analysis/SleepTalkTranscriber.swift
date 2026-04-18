import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation

/// 梦话转写。包装 `SFSpeechRecognizer`，强制 **on-device** 识别，不经网络。
///
/// 设计：
/// - 单次转写一个音频文件（事件 clip）→ 返回转写字符串，失败返回 nil
/// - 首次调用会触发权限请求
/// - 识别使用中文（`zh-CN`），如设备不支持则降级到默认 locale
/// - 不做实时流转写；Phase 2 只处理事件剪出来后的独立 clip
nonisolated final class SleepTalkTranscriber: @unchecked Sendable {

    private let recognizer: SFSpeechRecognizer?
    /// 已申请过权限后缓存结果，避免每次都走异步 callback。
    private var cachedAuthStatus: SFSpeechRecognizerAuthorizationStatus?

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        // 优先中文识别；若系统不支持则 fallback 到用户首选 locale
        self.recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer()
    }

    /// 转写一个音频文件。失败返回 nil（原始 clip 仍然保留，用户可播放）。
    /// 调用方应当已经判断事件类型为 `.sleepTalk`。
    func transcribe(url: URL) async -> String? {
        // 预校验：文件存在 + 有音轨。
        // 缺这一步时遇到 0-track 的退化 clip，SFSpeechURLRecognitionRequest 内部
        // 会让 AVAssetReader 同步抛 Obj-C NSException（Swift 无法 catch 直接崩）。
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("SleepTalkTranscriber: file does not exist: \(url.lastPathComponent)")
            return nil
        }
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard !tracks.isEmpty else {
                NSLog("SleepTalkTranscriber: clip has no audio tracks: \(url.lastPathComponent)")
                return nil
            }
        } catch {
            NSLog("SleepTalkTranscriber: failed to load tracks from \(url.lastPathComponent): \(error)")
            return nil
        }

        guard await ensureAuthorized() else { return nil }
        guard let recognizer, recognizer.isAvailable else {
            NSLog("SleepTalkTranscriber: recognizer unavailable")
            return nil
        }
        guard recognizer.supportsOnDeviceRecognition else {
            NSLog("SleepTalkTranscriber: on-device recognition not supported; skipping")
            return nil
        }

        return await withCheckedContinuation { cont in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false

            var hasResumed = false
            let lock = NSLock()
            func safeResume(_ value: String?) {
                lock.lock(); defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                cont.resume(returning: value)
            }

            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    NSLog("Speech recognition error: \(error)")
                    safeResume(nil)
                    return
                }
                guard let result else { return }
                if result.isFinal {
                    let text = result.bestTranscription.formattedString
                    safeResume(text.isEmpty ? nil : text)
                }
            }
        }
    }

    // MARK: - Permission

    /// 请求 / 查询 Speech 授权。已拒绝或不可用时返回 false。
    func ensureAuthorized() async -> Bool {
        if let cached = cachedAuthStatus {
            return cached == .authorized
        }
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        cachedAuthStatus = status
        return status == .authorized
    }
}
