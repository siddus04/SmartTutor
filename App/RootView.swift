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
<<<<<<< HEAD
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
=======
            List {
                NavigationLink("Exercises", destination: ExercisesHomeView())
                NavigationLink("Canvas Sandbox", destination: CanvasSandboxView())
            }
            .navigationTitle("SmartTutor")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        sessionStore.resetSession()
                    }
                }
#else
                ToolbarItem(placement: .automatic) {
                    Button("Reset") {
                        sessionStore.resetSession()
                    }
                }
#endif
            }
>>>>>>> f686a1d (wip before pull)
        }
    }
}
