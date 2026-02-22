import SwiftUI

struct RootView: View {
    @EnvironmentObject private var sessionStore: LearnerSessionStore

    var body: some View {
        Group {
            if sessionStore.isOnboardingComplete {
                canvasNavigation
            } else {
                OnboardingFlowView()
            }
        }
    }

    private var canvasNavigation: some View {
        NavigationStack {
            CanvasSandboxView()
        }
    }
}
