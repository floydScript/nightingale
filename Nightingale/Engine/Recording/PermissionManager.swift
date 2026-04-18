import Foundation
import AVFoundation
import Combine

/// 统一管理运行时权限。Phase 1A 只含麦克风。
@MainActor
final class PermissionManager: ObservableObject {

    enum MicStatus {
        case notDetermined
        case granted
        case denied
    }

    @Published private(set) var microphoneStatus: MicStatus = .notDetermined

    init() {
        refreshMicrophoneStatus()
    }

    /// 查当前权限状态（不触发弹窗）。
    func refreshMicrophoneStatus() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: microphoneStatus = .granted
        case .denied: microphoneStatus = .denied
        case .undetermined: microphoneStatus = .notDetermined
        @unknown default: microphoneStatus = .notDetermined
        }
    }

    /// 请求麦克风权限。已授权则立即返回 true，已拒绝返回 false（不会再弹）。
    func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphoneStatus = .granted
            return true
        case .denied:
            microphoneStatus = .denied
            return false
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            microphoneStatus = granted ? .granted : .denied
            return granted
        @unknown default:
            return false
        }
    }
}
