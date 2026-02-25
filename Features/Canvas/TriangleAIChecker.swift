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
        combinedPNGBase64: String,
        mergedImagePath: String?
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
            "merged_image_path": mergedImagePath,
            "combined_png_base64": combinedPNGBase64,
            "expected_answer_value": expectedAnswerValue
        ]
        let requestData = try? JSONSerialization.data(withJSONObject: payload, options: [])
        request.httpBody = requestData
        logRequest(url: url, payload: payload, requestData: requestData)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            logResponse(statusCode: statusCode, responseData: data)
            if let decoded = try? JSONDecoder().decode(TriangleAICheckResult.self, from: data) {
                return ResultEnvelope(result: decoded, statusCode: statusCode, didFallback: false)
            }
            return ResultEnvelope(result: mockResult(combinedPNGBase64: combinedPNGBase64), statusCode: statusCode, didFallback: true)
        } catch {
            return ResultEnvelope(result: mockResult(combinedPNGBase64: combinedPNGBase64), statusCode: nil, didFallback: true)
        }
    }

    private func logRequest(url: URL, payload: [String: Any?], requestData: Data?) {
        let safePayload: [String: Any] = payload.reduce(into: [:]) { partial, pair in
            if pair.key == "combined_png_base64" {
                partial[pair.key] = "<base64-redacted len=\((pair.value as? String)?.count ?? 0)>"
                return
            }
            partial[pair.key] = pair.value ?? NSNull()
        }
        print("[AICheck][Request] url=\(url.absoluteString)")
        if
            let data = try? JSONSerialization.data(withJSONObject: safePayload, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8) {
            print("[AICheck][Request] payload=\n\(text)")
        } else if let requestData {
            print("[AICheck][Request] payload=<unformatted bytes=\(requestData.count)>")
        }
    }

    private func logResponse(statusCode: Int?, responseData: Data) {
        print("[AICheck][Response] status=\(statusCode.map(String.init) ?? "nil") bytes=\(responseData.count)")
        if
            let object = try? JSONSerialization.jsonObject(with: responseData),
            let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: prettyData, encoding: .utf8) {
            print("[AICheck][Response] json=\n\(text)")
        } else if let raw = String(data: responseData, encoding: .utf8) {
            print("[AICheck][Response] raw=\(raw)")
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
