import SwiftUI

@main
@MainActor
struct DatenblickApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .tint(.telekomMagenta)
                .task { await model.refreshIfConfigured() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.refreshIfConfigured() }
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "datenblick", url.host == "refresh" else { return }
                    Task { await model.refresh() }
                }
        }
    }
}
