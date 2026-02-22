import SwiftUI

struct ExercisesHomeView: View {
    @EnvironmentObject private var sessionStore: LearnerSessionStore

    var body: some View {
        VStack(spacing: 16) {
            Text("Exercises Home")
                .font(.title)

            if let session = sessionStore.session {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Grade: \(session.learner.grade.displayName)")
                    Text("Topic: \(session.curriculum.topic.displayName)")
                    Text("Concept Graph: \(session.progression.conceptGraphId)")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }
}
