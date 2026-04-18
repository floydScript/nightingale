import SwiftUI
import SwiftData
import Combine

/// 智能闹钟设置页（Phase 3 · P3.1）。
/// 从 SettingsView 的"智能闹钟"条目推入；单行 `AlarmSettings` 承载状态。
/// 保存时会调 `SmartAlarmScheduler.rescheduleIfNeeded(_:)` 立即排一次通知。
struct AlarmView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allSettings: [AlarmSettings]
    @StateObject private var scheduler = SmartAlarmSchedulerHolder()

    // 编辑缓冲
    @State private var enabled = false
    @State private var targetTime: Date = AlarmSettings.defaultTargetTime
    @State private var windowMinutes: Int = 20
    @State private var hydrated = false
    @State private var permissionDenied = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Form {
                Section {
                    Toggle("启用智能闹钟", isOn: $enabled)
                        .tint(Theme.accent)
                } footer: {
                    Text("我们会在你设定的目标时间前，找一个相对好唤醒的浅睡时刻推送本地通知；若找不到就在目标时间准点唤醒。")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)

                Section("目标唤醒时间") {
                    DatePicker("最晚唤醒", selection: $targetTime, displayedComponents: .hourAndMinute)
                        .tint(Theme.accent)
                }
                .listRowBackground(Theme.surface)

                Section("起床窗口") {
                    Stepper(value: $windowMinutes, in: 10...30, step: 5) {
                        HStack {
                            Text("窗口长度")
                            Spacer()
                            Text("\(windowMinutes) 分钟").foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                if permissionDenied {
                    Section {
                        Text("通知权限被拒绝，请到「系统设置 → Nightingale → 通知」开启后重试。")
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    Button {
                        Task { await saveAndSchedule() }
                    } label: {
                        HStack {
                            Spacer()
                            Text("保存并排程")
                                .bold()
                                .foregroundStyle(Color.black)
                            Spacer()
                        }
                    }
                    .listRowBackground(Theme.accent)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("智能闹钟")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: hydrate)
    }

    // MARK: - Logic

    private func hydrate() {
        guard !hydrated else { return }
        if let s = allSettings.first {
            enabled = s.isEnabled
            targetTime = s.targetTime
            windowMinutes = s.windowMinutes
        }
        hydrated = true
    }

    private func saveAndSchedule() async {
        let settings: AlarmSettings
        if let existing = allSettings.first {
            settings = existing
        } else {
            settings = AlarmSettings()
            modelContext.insert(settings)
        }
        settings.isEnabled = enabled
        settings.targetTime = targetTime
        settings.windowMinutes = windowMinutes
        try? modelContext.save()

        if enabled {
            let granted = await scheduler.alarm.requestAuthorization()
            permissionDenied = !granted
            if granted {
                await scheduler.alarm.rescheduleIfNeeded(settings: settings)
                dismiss()
            }
        } else {
            await scheduler.alarm.cancelAll()
            dismiss()
        }
    }
}

/// 把 `SmartAlarmScheduler` 包成 @StateObject 方便 view 持有。
@MainActor
private final class SmartAlarmSchedulerHolder: ObservableObject {
    let alarm = SmartAlarmScheduler()
    // ObservableObject 没有 @Published 时编译能通过（Swift 5.9+），但给个 dummy 保险
    @Published private var _tick = false
}
