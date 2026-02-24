import Foundation

protocol TriangleAPIClient {
    func generateQuestion(conceptId: String, grade: Int, target: DifficultyTarget, allowedInteractionTypes: [String]) async throws -> GeneratedQuestionEnvelope
    func rateDifficulty(questionSpec: QuestionSpec, grade: Int) async throws -> DifficultyRating
}

struct GeneratedQuestionEnvelope: Codable {
    let questionSpec: QuestionSpec

    enum CodingKeys: String, CodingKey {
        case questionSpec = "question_spec"
    }
}

enum TriangleAPI {
    static func generateQuestion() async throws -> TriangleResponse {
        try await StubQuestionProvider().generateQuestion(conceptId: "tri.structure.hypotenuse", difficulty: 1, intent: .teach)
    }
}

struct LiveTriangleAPIClient: TriangleAPIClient {
    func generateQuestion(conceptId: String, grade: Int, target: DifficultyTarget, allowedInteractionTypes: [String]) async throws -> GeneratedQuestionEnvelope {
        guard let url = URL(string: AppConfig.baseURL + "/api/triangles/generate") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = GenerateQuestionRequest(
            conceptId: conceptId,
            grade: grade,
            targetBand: target.band.map { DifficultyBand(min: $0.lowerBound, max: $0.upperBound) },
            targetDirection: target.direction?.rawValue,
            allowedInteractionTypes: allowedInteractionTypes,
            learnerContext: [:]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try ensureSuccess(response: response)
        return try JSONDecoder().decode(GeneratedQuestionEnvelope.self, from: data)
    }

    func rateDifficulty(questionSpec: QuestionSpec, grade: Int) async throws -> DifficultyRating {
        guard let url = URL(string: AppConfig.baseURL + "/api/triangles/rate") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = RateDifficultyRequest(questionSpec: questionSpec, grade: grade)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try ensureSuccess(response: response)
        return try JSONDecoder().decode(DifficultyRating.self, from: data)
    }

    private func ensureSuccess(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

private struct GenerateQuestionRequest: Codable {
    let conceptId: String
    let grade: Int
    let targetBand: DifficultyBand?
    let targetDirection: String?
    let allowedInteractionTypes: [String]
    let learnerContext: [String: String]

    enum CodingKeys: String, CodingKey {
        case conceptId = "concept_id"
        case grade
        case targetBand = "target_band"
        case targetDirection = "target_direction"
        case allowedInteractionTypes = "allowed_interaction_types"
        case learnerContext = "learner_context"
    }
}

private struct DifficultyBand: Codable {
    let min: Int
    let max: Int
}

private struct RateDifficultyRequest: Codable {
    let questionSpec: QuestionSpec
    let grade: Int

    enum CodingKeys: String, CodingKey {
        case questionSpec = "question_spec"
        case grade
    }
}
