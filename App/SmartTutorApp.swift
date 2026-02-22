import SwiftUI

@main
struct SmartTutorApp: App {
    @StateObject private var sessionStore = LearnerSessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionStore)
                .onAppear {
                    sessionStore.loadSession()
                }
        }
    }
}
