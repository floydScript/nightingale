import SwiftUI
import SwiftData

struct AppRoot: View {

    let fileStore: AudioFileStore
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var healthKit: HealthKitSync
    @ObservedObject var controller: RecorderController

    var body: some View {
        TabView {
            TonightView(controller: controller)
                .tabItem { Label("今夜", systemImage: "moon.stars.fill") }

            ReportListView(fileStore: fileStore)
                .tabItem { Label("报告", systemImage: "chart.xyaxis.line") }

            TrendsView()
                .tabItem { Label("趋势", systemImage: "chart.line.uptrend.xyaxis") }

            ArchiveView(fileStore: fileStore)
                .tabItem { Label("档案", systemImage: "books.vertical.fill") }

            SettingsView(
                fileStore: fileStore,
                permissions: permissions,
                healthKit: healthKit
            )
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
    }
}
