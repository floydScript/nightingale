import SwiftUI

struct TonightView: View {

    @ObservedObject var controller: RecorderController

    /// 证书 banner 本地关闭状态（只管本次 app 生命周期，重启会再弹）。
    @State private var dismissedCertWarning = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                if showCertBanner {
                    certBanner.padding(.horizontal, Theme.padding)
                }
                VStack(spacing: 32) {
                    Spacer()
                    headline
                    Spacer()
                    bigButton
                    subtitle
                    Spacer().frame(height: 60)
                }
                .padding(.horizontal, Theme.padding)
            }
        }
    }

    // MARK: Phase 1 Tail · T1.2 证书 banner

    private var showCertBanner: Bool {
        CertExpiry.shouldWarnOnHome() && !dismissedCertWarning
    }

    private var certBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.35))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("证书即将过期（\(CertExpiry.shortStatus())）")
                    .font(.subheadline).bold()
                    .foregroundStyle(Theme.textPrimary)
                Text("请将手机插回 Mac 重新部署，否则明晚 app 可能无法启动。")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                dismissedCertWarning = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(red: 0.30, green: 0.23, blue: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    @ViewBuilder
    private var headline: some View {
        switch controller.state {
        case .idle:
            VStack(spacing: 6) {
                Text("准备就绪")
                    .font(.title).bold()
                    .foregroundStyle(Theme.textPrimary)
                Text("把手机放在床头，屏幕朝下,插上电源")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        case .recording(let start):
            VStack(spacing: 6) {
                Text("正在记录")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Text(TimeFormat.duration(Date().timeIntervalSince(start)))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Text("息屏不会中断录音")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        case .finalizing:
            VStack(spacing: 8) {
                ProgressView().tint(Theme.accent)
                Text("正在保存…")
                    .foregroundStyle(Theme.textSecondary)
            }
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.danger)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    @ViewBuilder
    private var bigButton: some View {
        Button {
            handleTap()
        } label: {
            ZStack {
                Circle()
                    .fill(buttonColor)
                    .frame(width: 200, height: 200)
                    .shadow(color: buttonColor.opacity(0.5), radius: 40)
                Text(buttonLabel)
                    .font(.title2).bold()
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(isButtonDisabled)
    }

    private var subtitle: some View {
        Text(subtitleText)
            .font(.footnote)
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
    }

    private func handleTap() {
        switch controller.state {
        case .idle:
            Task { await controller.start() }
        case .recording:
            controller.stop()
        case .failed:
            Task { await controller.start() }
        case .finalizing:
            break
        }
    }

    private var buttonLabel: String {
        switch controller.state {
        case .idle: "开始记录"
        case .recording: "结束记录"
        case .finalizing: "保存中"
        case .failed: "重试"
        }
    }

    private var buttonColor: Color {
        switch controller.state {
        case .idle: Theme.accent
        case .recording: Theme.danger
        case .finalizing: Theme.textTertiary
        case .failed: Theme.danger
        }
    }

    private var isButtonDisabled: Bool {
        if case .finalizing = controller.state { return true }
        return false
    }

    private var subtitleText: String {
        switch controller.state {
        case .idle, .failed:
            return "开始后手机可以熄屏，静音。早上醒来回到 app 点「结束记录」。"
        case .recording:
            return "不要关闭 app，不要手动结束进程。"
        case .finalizing:
            return ""
        }
    }
}
