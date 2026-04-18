import SwiftUI
import SwiftData

struct SettingsView: View {

    let fileStore: AudioFileStore
    @ObservedObject var permissions: PermissionManager

    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [SleepSession]

    @State private var showWipeConfirm = false
    @State private var storageBytes: Int64 = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                List {
                    Section("权限") {
                        permissionRow("麦克风", status: micStatusText, color: micStatusColor)
                    }
                    .listRowBackground(Theme.surface)

                    Section("存储") {
                        row(label: "录音文件", value: bytesText(storageBytes))
                        row(label: "记录数", value: "\(sessions.count)")
                    }
                    .listRowBackground(Theme.surface)

                    Section {
                        Button(role: .destructive) {
                            showWipeConfirm = true
                        } label: {
                            Text("一键清空所有数据")
                        }
                    }
                    .listRowBackground(Theme.surface)

                    Section("版本") {
                        row(label: "Nightingale", value: "Phase 1A")
                    }
                    .listRowBackground(Theme.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("设置")
            .onAppear {
                permissions.refreshMicrophoneStatus()
                storageBytes = fileStore.totalBytesUsed()
            }
            .confirmationDialog("确认清空？", isPresented: $showWipeConfirm) {
                Button("清空所有录音", role: .destructive, action: wipeAll)
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有整夜录音文件和 session 记录会被永久删除，不可恢复。")
            }
        }
    }

    private var micStatusText: String {
        switch permissions.microphoneStatus {
        case .granted: "已授权"
        case .denied: "已拒绝（请到系统设置开启）"
        case .notDetermined: "尚未请求"
        }
    }

    private var micStatusColor: Color {
        switch permissions.microphoneStatus {
        case .granted: Theme.accent
        case .denied: Theme.danger
        case .notDetermined: Theme.textTertiary
        }
    }

    private func permissionRow(_ name: String, status: String, color: Color) -> some View {
        HStack {
            Text(name).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(status).foregroundStyle(color).font(.subheadline)
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary).font(.system(.body, design: .monospaced))
        }
    }

    private func bytesText(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }

    private func wipeAll() {
        try? FileManager.default.removeItem(at: fileStore.recordingsDirectory)
        for s in sessions { modelContext.delete(s) }
        try? modelContext.save()
        storageBytes = 0
    }
}
