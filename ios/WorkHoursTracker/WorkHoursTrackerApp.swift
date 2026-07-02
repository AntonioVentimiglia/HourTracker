import SwiftUI

@main
struct WorkHoursTrackerApp: App {
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.bootstrap() }
        }
    }
}
