import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct NightingaleApp: App {

    static let cleanupTaskIdentifier = "com.floydscript.nightingale.cleanup"

    let modelContainer: ModelContainer
    let fileStore: AudioFileStore
    let permissions: PermissionManager
    let healthKit: HealthKitSync
    let recorderController: RecorderController

    init() {
        let schema = Schema([
            SleepSession.self,
            SleepEvent.self,
            SensorSample.self,
            AlarmSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }

        let store = AudioFileStore()
        let perms = PermissionManager()
        let hk = HealthKitSync()
        let clipExtractor = ClipExtractor(fileStore: store)
        let rc = RecorderController(
            modelContext: container.mainContext,
            fileStore: store,
            permissions: perms,
            healthKit: hk,
            clipExtractor: clipExtractor
        )

        self.modelContainer = container
        self.fileStore = store
        self.permissions = perms
        self.healthKit = hk
        self.recorderController = rc

        // 注册后台清理任务（T1.3）。必须在 init / applicationDidFinishLaunching 前注册，
        // 否则 BGTaskScheduler 会在首次提交任务时报错。
        Self.registerCleanupTask(fileStore: store, container: container)
        // 同时现在就 schedule 一次，让系统知道该 app 想要后台时间窗口
        Self.scheduleCleanupTask()
        // App 启动即做一次（belt-and-suspenders），不依赖系统给不给窗口
        Task.detached { @Sendable in
            await Self.runCleanupNow(fileStore: store, container: container)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRoot(
                fileStore: fileStore,
                permissions: permissions,
                healthKit: healthKit,
                controller: recorderController
            )
            .modelContainer(modelContainer)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - BGTaskScheduler (Phase 1 Tail T1.3)

    private static func registerCleanupTask(fileStore: AudioFileStore, container: ModelContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.cleanupTaskIdentifier,
            using: nil
        ) { task in
            // 立刻重排一次下一轮
            Self.scheduleCleanupTask()
            Task.detached { @Sendable in
                await Self.runCleanupNow(fileStore: fileStore, container: container)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                task.setTaskCompleted(success: false)
            }
        }
    }

    private static func scheduleCleanupTask() {
        let req = BGProcessingTaskRequest(identifier: Self.cleanupTaskIdentifier)
        req.requiresNetworkConnectivity = false
        req.requiresExternalPower = false
        req.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)  // 下次机会 6 小时后
        do {
            try BGTaskScheduler.shared.submit(req)
        } catch {
            // 在模拟器或未配置 Info.plist 时 submit 会失败；启动时的一次性清理能兜底。
            NSLog("BGTaskScheduler submit failed: \(error)")
        }
    }

    /// 实际执行清理。拉 isArchived = true 的 session ID，避免误删已归档的晚上。
    private static func runCleanupNow(fileStore: AudioFileStore, container: ModelContainer) async {
        let archivedIDs = await MainActor.run { () -> Set<UUID> in
            let ctx = container.mainContext
            let descriptor = FetchDescriptor<SleepSession>(
                predicate: #Predicate { $0.isArchived == true }
            )
            let archived = (try? ctx.fetch(descriptor)) ?? []
            return Set(archived.map(\.id))
        }
        do {
            let removed = try fileStore.cleanupOldRecordings(olderThan: 7, archivedIDs: archivedIDs)
            if !removed.isEmpty {
                NSLog("Cleanup removed \(removed.count) old recordings")
            }
        } catch {
            NSLog("Cleanup error: \(error)")
        }
    }
}
