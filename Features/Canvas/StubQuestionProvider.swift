import Foundation

protocol TriangleQuestionProviding {
    func generateQuestion(conceptId: String, difficulty: Int, intent: LearningIntent) async throws -> TriangleResponse
}

struct StubQuestionProvider: TriangleQuestionProviding {
    func generateQuestion(conceptId: String, difficulty: Int, intent: LearningIntent) async throws -> TriangleResponse {
        let cappedDifficulty = min(max(difficulty, 1), SessionStorage.grade6DifficultyCeiling)
        let variant = cappedDifficulty % 3
        let answer = variant == 0 ? "AB" : (variant == 1 ? "BC" : "CA")

        return TriangleResponse(
            bundleId: "stub.\(conceptId).d\(cappedDifficulty).\(intent.rawValue)",
            base: TriangleBase(
                tutorMessages: [
                    TriangleTutorMessage(role: "assistant", text: "Concept: \(conceptId)"),
                    TriangleTutorMessage(role: "assistant", text: "Difficulty \(cappedDifficulty) · Intent \(intent.rawValue)."),
                    TriangleTutorMessage(role: "assistant", text: "Circle side \(answer).")
                ],
                diagramSpec: TriangleDiagramSpec(
                    points: [
                        "A": TrianglePoint(x: 0.2 + 0.01 * Double(cappedDifficulty), y: 0.78),
                        "B": TrianglePoint(x: 0.8, y: 0.78),
                        "C": TrianglePoint(x: 0.52, y: 0.18 + 0.03 * Double(variant))
                    ],
                    segments: ["AB", "BC", "CA"],
                    vertexLabels: ["A": "A", "B": "B", "C": "C"],
                    rightAngleAt: cappedDifficulty <= 2 ? "C" : nil
                ),
                answer: TriangleAnswer(value: answer),
                conceptId: conceptId,
                difficulty: cappedDifficulty,
                intent: intent.rawValue
            )
        )
    }
}
