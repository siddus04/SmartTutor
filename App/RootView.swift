import SwiftUI

struct RootView: View {
    @EnvironmentObject private var sessionStore: LearnerSessionStore

    var body: some View {
        Group {
            if sessionStore.isOnboardingComplete {
                mainNavigation
            } else {
                OnboardingFlowView()
            }
        }
    }

    private var mainNavigation: some View {
        NavigationStack {
            CanvasSandboxView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("SmartTutor")
                            .font(.headline)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Reset") {
                            sessionStore.resetSession()
                        }
                    }
                }
        }
    }
}
