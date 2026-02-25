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
    struct ResultEnvelope {
        let result: TriangleAICheckResult
        let statusCode: Int?
        let didFallback: Bool
    }

    func check(
        conceptId: String,
        promptText: String,
        interactionType: String,
        responseMode: String,
        rightAngleAt: String?,
        expectedAnswerValue: String,
        combinedPNGBase64: String
    ) async -> ResultEnvelope {
        guard let url = URL(string: AppConfig.aiCheckBaseURL + "api/triangles/check") else {
            return ResultEnvelope(result: mockResult(combinedPNGBase64: combinedPNGBase64), statusCode: nil, didFallback: true)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let payload: [String: Any?] = [
            "concept_id": conceptId,
            "prompt_text": promptText,
            "interaction_type": interactionType,
            "response_mode": responseMode,
            "right_angle_at": rightAngleAt,
            "combined_png_base64": combinedPNGBase64,
            "expected_answer_value": expectedAnswerValue
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            if let decoded = try? JSONDecoder().decode(TriangleAICheckResult.self, from: data) {
                return ResultEnvelope(result: decoded, statusCode: statusCode, didFallback: false)
            }
            return ResultEnvelope(result: mockResult(combinedPNGBase64: combinedPNGBase64), statusCode: statusCode, didFallback: true)
        } catch {
            return ResultEnvelope(result: mockResult(combinedPNGBase64: combinedPNGBase64), statusCode: nil, didFallback: true)
        }
    }

    private func mockResult(combinedPNGBase64: String) -> TriangleAICheckResult {
        if !combinedPNGBase64.isEmpty {
            return TriangleAICheckResult(
                detectedSegment: "AB",
                ambiguityScore: 0.25,
                confidence: 0.75,
                reasonCodes: ["MOCK_MODE"],
                studentFeedback: "*(AI check - mock)* I can see a circle near one side. Re-check the prompt and side labels."
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
