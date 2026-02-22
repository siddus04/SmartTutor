import SwiftUI

struct OnboardingFlowView: View {
    enum Step {
        case grade
        case topic
    }

    @EnvironmentObject private var sessionStore: LearnerSessionStore
    @State private var step: Step = .grade
    @State private var selectedGrade: GradeLevel = .grade6

    var body: some View {
        NavigationStack {
            switch step {
            case .grade:
                GradeSelectionView { grade in
                    selectedGrade = grade
                    step = .topic
                }
            case .topic:
                TopicSelectionView(selectedGrade: selectedGrade) { topic in
                    sessionStore.initializeSession(grade: selectedGrade, topic: topic)
                }
            }
        }
    }
}
