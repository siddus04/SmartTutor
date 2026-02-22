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
            List {
                NavigationLink("Exercises", destination: ExercisesHomeView())
                NavigationLink("Canvas Sandbox", destination: CanvasSandboxView())
            }
            .navigationTitle("SmartTutor")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        sessionStore.resetSession()
                    }
                }
            }
        }
    }
}
