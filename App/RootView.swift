import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Exercises", destination: ExercisesHomeView())
                NavigationLink("Canvas Sandbox", destination: CanvasSandboxView())
            }
            .navigationTitle("SmartTutor")
        }
    }
}
