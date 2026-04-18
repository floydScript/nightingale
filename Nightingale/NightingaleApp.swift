import SwiftUI
import SwiftData

@main
struct NightingaleApp: App {

    let modelContainer: ModelContainer
    let fileStore: AudioFileStore
    let permissions: PermissionManager
    let recorderController: RecorderController

    init() {
        let schema = Schema([SleepSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }

        let store = AudioFileStore()
        let perms = PermissionManager()
        let rc = RecorderController(
            modelContext: container.mainContext,
            fileStore: store,
            permissions: perms
        )

        self.modelContainer = container
        self.fileStore = store
        self.permissions = perms
        self.recorderController = rc
    }

    var body: some Scene {
        WindowGroup {
            AppRoot(
                fileStore: fileStore,
                permissions: permissions,
                controller: recorderController
            )
            .modelContainer(modelContainer)
            .preferredColorScheme(.dark)
        }
    }
}
