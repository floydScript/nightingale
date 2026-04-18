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
///
/// 诊断：每一步失败都 NSLog，方便在 Xcode console 里看"到底为什么没转写"。
nonisolated final class SleepTalkTranscriber: @unchecked Sendable {

    private let recognizer: SFSpeechRecognizer?
    /// 已申请过权限后缓存结果。
    private var cachedAuthStatus: SFSpeechRecognizerAuthorizationStatus?
    /// 单次识别的最长等待时间。避免 task 卡死无限挂起。
    private let recognitionTimeoutSeconds: UInt64 = 30

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        let primary = SFSpeechRecognizer(locale: locale)
        let final = primary ?? SFSpeechRecognizer()
        self.recognizer = final

        if let r = final {
            NSLog("SleepTalkTranscriber init: locale=\(r.locale.identifier) isAvailable=\(r.isAvailable) supportsOnDevice=\(r.supportsOnDeviceRecognition)")
        } else {
            NSLog("SleepTalkTranscriber init: no recognizer available at all")
        }
    }

    /// 转写一个音频文件。失败返回 nil（原始 clip 仍然保留，用户可播放）。
    /// 调用方应当已经判断事件类型为 `.sleepTalk`。
    func transcribe(url: URL) async -> String? {
        NSLog("SleepTalkTranscriber: transcribe \(url.lastPathComponent) START")

        // 预校验：文件存在 + 有音轨（防 AVAssetReader NSException 崩溃）。
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("SleepTalkTranscriber: file not found")
            return nil
        }
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard !tracks.isEmpty else {
                NSLog("SleepTalkTranscriber: clip has 0 audio tracks")
                return nil
            }
            if let duration = try? await asset.load(.duration) {
                NSLog("SleepTalkTranscriber: clip duration=\(String(format: "%.2f", duration.seconds))s")
            }
        } catch {
            NSLog("SleepTalkTranscriber: failed to load tracks: \(error)")
            return nil
        }

        guard await ensureAuthorized() else {
            NSLog("SleepTalkTranscriber: not authorized (status=\(authStatusString))")
            return nil
        }
        guard let recognizer else {
            NSLog("SleepTalkTranscriber: recognizer is nil")
            return nil
        }
        guard recognizer.isAvailable else {
            NSLog("SleepTalkTranscriber: recognizer not currently available (Siri/dictation maybe off)")
            return nil
        }
        guard recognizer.supportsOnDeviceRecognition else {
            NSLog("SleepTalkTranscriber: on-device recognition NOT supported for locale \(recognizer.locale.identifier). Go to iPhone 设置 → 通用 → 键盘 → 听写：确保中文（普通话）已启用；必要时在 Siri 语言设置里选中文让其下载离线模型。")
            return nil
        }

        NSLog("SleepTalkTranscriber: dispatching recognition task (on-device, locale=\(recognizer.locale.identifier))")

        let startTime = Date()
        let result: String? = await withCheckedContinuation { cont in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.requiresOnDeviceRecognition = true
            // 开 partial 让 recognizer 把中间识别到的字不断送回来。诊断用：
            // 若 partial 出过非空而 final 变空，说明识别了但 finalizer 吞了；
            // 若 partial 始终空，说明音频本身未被识别到任何 token。
            request.shouldReportPartialResults = true
            request.addsPunctuation = true

            let state = ResumeGuard()
            var lastPartial = ""
            var partialCount = 0

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    let nsError = error as NSError
                    NSLog("SleepTalkTranscriber: recognition error domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)")
                    state.resume(with: nil, cont: cont)
                    return
                }
                guard let result else { return }

                let text = result.bestTranscription.formattedString

                if !result.isFinal {
                    partialCount += 1
                    if text != lastPartial {
                        NSLog("SleepTalkTranscriber: partial[\(partialCount)]=\"\(text)\"")
                        lastPartial = text
                    }
                    return
                }

                // final：若 text 为空但中间有过非空 partial，用最后一次 partial 作为结果（iOS 奇葩行为兜底）
                let elapsed = Date().timeIntervalSince(startTime)
                let chosen = !text.isEmpty ? text : lastPartial
                NSLog("SleepTalkTranscriber: final text=\"\(text)\" lastPartial=\"\(lastPartial)\" chosen=\"\(chosen)\" elapsed=\(String(format: "%.2f", elapsed))s")
                state.resume(with: chosen.isEmpty ? nil : chosen, cont: cont)
            }

            // Timeout safety net.
            Task {
                try? await Task.sleep(nanoseconds: self.recognitionTimeoutSeconds * 1_000_000_000)
                if !state.hasResumed() {
                    NSLog("SleepTalkTranscriber: recognition timeout after \(self.recognitionTimeoutSeconds)s, canceling task")
                    task.cancel()
                    state.resume(with: nil, cont: cont)
                }
            }
        }

        NSLog("SleepTalkTranscriber: transcribe \(url.lastPathComponent) DONE result=\(result == nil ? "nil" : "\"\(result!)\"")")
        return result
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

    private var authStatusString: String {
        switch cachedAuthStatus {
        case .some(.authorized): return "authorized"
        case .some(.denied): return "denied"
        case .some(.restricted): return "restricted"
        case .some(.notDetermined): return "notDetermined"
        case .some(let other): return "other(\(other.rawValue))"
        case .none: return "unknown"
        }
    }
}

/// 保证 withCheckedContinuation 只 resume 一次的小状态盒。
private nonisolated final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func hasResumed() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return resumed
    }

    func resume(with value: String?, cont: CheckedContinuation<String?, Never>) {
        lock.lock()
        if resumed {
            lock.unlock()
            return
        }
        resumed = true
        lock.unlock()
        cont.resume(returning: value)
    }
}
