import SwiftUI

@main
struct WorkHoursTrackerApp: App {
    @StateObject private var store = AppStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.bootstrap() }
        }
        // Siri and Shortcuts can clock in/out from a background process while
        // this app isn't the active one; re-sync from the server whenever we
        // come back to the foreground so that state isn't stale.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, store.isAuthenticated else { return }
            Task { await store.refreshAll() }
        }
    }
}
