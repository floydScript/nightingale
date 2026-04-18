import SwiftUI
import SwiftData

@main
struct NightingaleApp: App {

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
}
