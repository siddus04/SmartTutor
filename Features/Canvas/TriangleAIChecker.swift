import Foundation

struct TriangleAICheckResult: Codable {
    let detectedSegment: String?
    let ambiguityScore: Double
    let confidence: Double
    let reasonCodes: [String]
    let studentFeedback: String

    enum CodingKeys: String, CodingKey {
        case detectedSegment = "detected_segment"
        case ambiguityScore = "ambiguity_score"
        case confidence
        case reasonCodes = "reason_codes"
        case studentFeedback = "student_feedback"
    }
}

final class TriangleAIChecker {
    func check(concept: String, task: String, combinedPNGBase64: String) async -> TriangleAICheckResult {
        try? await Task.sleep(nanoseconds: 800_000_000)
        if !combinedPNGBase64.isEmpty {
            return TriangleAICheckResult(
                detectedSegment: "AB",
                ambiguityScore: 0.25,
                confidence: 0.75,
                reasonCodes: ["MOCK_MODE"],
                studentFeedback: "*(AI check - mock)* I can see a circle near the base. If you meant the hypotenuse, remember it’s opposite the right angle."
            )
        }
        return TriangleAICheckResult(
            detectedSegment: nil,
            ambiguityScore: 1.0,
            confidence: 0.0,
            reasonCodes: ["MOCK_MODE", "EMPTY_INPUT"],
            studentFeedback: "*(AI check - mock)* I couldn't read the drawing."
        )
    }
}
