import SwiftUI

struct TopicSelectionView: View {
    let selectedGrade: GradeLevel
    let onStart: (TopicKey) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Grade 6")
                .font(.headline)

            Text("Choose your topic")
                .font(.title2)
                .fontWeight(.bold)

            Button {
                onStart(.geometryTriangles)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Geometry → Triangles")
                        .font(.headline)
                    Text("Includes right triangles up to Pythagoras")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text("MVP scope is limited to this topic")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Topic")
    }
}
