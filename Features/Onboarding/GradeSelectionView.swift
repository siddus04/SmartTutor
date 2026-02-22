import SwiftUI

struct GradeSelectionView: View {
    let onContinue: (GradeLevel) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to SmartTutor")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Choose your grade")
                .font(.headline)

            Button {
                onContinue(.grade6)
            } label: {
                Text("Grade 6")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text("MVP supports Grade 6 only")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Onboarding")
    }
}
