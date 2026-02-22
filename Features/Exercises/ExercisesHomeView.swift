import SwiftUI

struct ExercisesHomeView: View {
    @EnvironmentObject private var sessionStore: LearnerSessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Learning Hub")
                    .font(.title)
                    .fontWeight(.semibold)

                continueLearningCard

                currentTopicCard

                progressCard

                if let session = sessionStore.session {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session Diagnostics")
                            .font(.subheadline)
                            .fontWeight(.semibold)
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
        .navigationTitle("Learning Hub")
    }

    private var continueLearningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Learning")
                .font(.headline)
            Text("Return to your active Geometry → Triangles lesson and continue from where you left off.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Continue Learning") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var currentTopicCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Topic")
                .font(.headline)
            Text("Grade 6 • Geometry → Triangles")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("You are currently learning triangle structure, properties, and Pythagoras within the MVP scope.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progress (coming soon)")
                .font(.headline)
            Text("Mastery tracking and concept-level progress summaries will appear here in a future milestone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
