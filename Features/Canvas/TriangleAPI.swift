import Foundation
import CryptoKit

struct DifficultyTarget {
    let band: ClosedRange<Int>?
    let direction: DifficultyDirection?

    static func from(intent: LearningIntent, difficulty: Int) -> DifficultyTarget {
        let clamped = min(max(difficulty, 1), SessionStorage.grade6DifficultyCeiling)
        let direction: DifficultyDirection
        switch intent {
        case .remediate:
            direction = .easier
        case .teach, .practice:
            direction = .same
        case .assess:
            direction = .harder
        }
        let lower = max(1, clamped - 1)
        let upper = min(SessionStorage.grade6DifficultyCeiling, clamped + 1)
        return DifficultyTarget(band: lower...upper, direction: direction)
    }
}

enum DifficultyDirection: String, Codable {
    case easier
    case same
    case harder
}

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

        let learnerContext = await LearnerContextStore.shared.snapshot()
        let payload = GenerateQuestionRequest(
            conceptId: conceptId,
            grade: grade,
            targetBand: target.band.map { DifficultyBand(min: $0.lowerBound, max: $0.upperBound) },
            targetDirection: target.direction?.rawValue,
            allowedInteractionTypes: allowedInteractionTypes,
            learnerContext: learnerContext
        )
        let requestData = try JSONEncoder().encode(payload)
        request.httpBody = requestData
        logJSON("[TriangleAPI][Generate][Request]", data: requestData)

        let (data, response) = try await URLSession.shared.data(for: request)
        logHTTP("[TriangleAPI][Generate]", response: response)
        logJSON("[TriangleAPI][Generate][Response]", data: data)
        try ensureSuccess(response: response)
        let envelope = try JSONDecoder().decode(GeneratedQuestionEnvelope.self, from: data)
        await LearnerContextStore.shared.record(questionSpec: envelope.questionSpec)
        return envelope
    }

    func rateDifficulty(questionSpec: QuestionSpec, grade: Int) async throws -> DifficultyRating {
        guard let url = URL(string: AppConfig.baseURL + "/api/triangles/rate") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = RateDifficultyRequest(questionSpec: questionSpec, grade: grade)
        let requestData = try JSONEncoder().encode(payload)
        request.httpBody = requestData
        logJSON("[TriangleAPI][Rate][Request]", data: requestData)

        let (data, response) = try await URLSession.shared.data(for: request)
        logHTTP("[TriangleAPI][Rate]", response: response)
        logJSON("[TriangleAPI][Rate][Response]", data: data)
        try ensureSuccess(response: response)
        return try JSONDecoder().decode(DifficultyRating.self, from: data)
    }

    private func ensureSuccess(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func logHTTP(_ prefix: String, response: URLResponse) {
        guard let http = response as? HTTPURLResponse else {
            print("\(prefix) response=<non-http>")
            return
        }
        print("\(prefix) status=\(http.statusCode) url=\(http.url?.absoluteString ?? "nil")")
    }

    private func logJSON(_ prefix: String, data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: prettyData, encoding: .utf8)
        else {
            let fallback = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("\(prefix) \(fallback)")
            return
        }

        print("\(prefix)\n\(text)")
    }
}

private struct GenerateQuestionRequest: Codable {
    let conceptId: String
    let grade: Int
    let targetBand: DifficultyBand?
    let targetDirection: String?
    let allowedInteractionTypes: [String]
    let learnerContext: LearnerContextPayload

    enum CodingKeys: String, CodingKey {
        case conceptId = "concept_id"
        case grade
        case targetBand = "target_band"
        case targetDirection = "target_direction"
        case allowedInteractionTypes = "allowed_interaction_types"
        case learnerContext = "learner_context"
    }
}

private struct LearnerContextPayload: Codable {
    let recentConceptIds: [String]
    let recentPromptHashes: [String]
    let recentInteractionTypes: [String]
    let recentExpectedAnswers: [String]
    let recentQuestionFamilies: [String]

    enum CodingKeys: String, CodingKey {
        case recentConceptIds = "recent_concept_ids"
        case recentPromptHashes = "recent_prompt_hashes"
        case recentInteractionTypes = "recent_interaction_types"
        case recentExpectedAnswers = "recent_expected_answers"
        case recentQuestionFamilies = "recent_question_families"
    }

    init(recentConceptIds: [String], recentPromptHashes: [String], recentInteractionTypes: [String], recentExpectedAnswers: [String], recentQuestionFamilies: [String]) {
        self.recentConceptIds = recentConceptIds
        self.recentPromptHashes = recentPromptHashes
        self.recentInteractionTypes = recentInteractionTypes
        self.recentExpectedAnswers = recentExpectedAnswers
        self.recentQuestionFamilies = recentQuestionFamilies
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recentConceptIds = try c.decodeIfPresent([String].self, forKey: .recentConceptIds) ?? []
        recentPromptHashes = try c.decodeIfPresent([String].self, forKey: .recentPromptHashes) ?? []
        recentInteractionTypes = try c.decodeIfPresent([String].self, forKey: .recentInteractionTypes) ?? []
        recentExpectedAnswers = try c.decodeIfPresent([String].self, forKey: .recentExpectedAnswers) ?? []
        recentQuestionFamilies = try c.decodeIfPresent([String].self, forKey: .recentQuestionFamilies) ?? []
    }
}

private actor LearnerContextStore {
    static let shared = LearnerContextStore()
    private static let storageKey = "smarttutor.learnerContext.v1"
    private let maxHistoryCount = 8

    private var recentConceptIds: [String] = []
    private var recentPromptHashes: [String] = []
    private var recentInteractionTypes: [String] = []
    private var recentExpectedAnswers: [String] = []
    private var recentQuestionFamilies: [String] = []

    init() {
        restore()
    }

    func snapshot() -> LearnerContextPayload {
        LearnerContextPayload(
            recentConceptIds: recentConceptIds,
            recentPromptHashes: recentPromptHashes,
            recentInteractionTypes: recentInteractionTypes,
            recentExpectedAnswers: recentExpectedAnswers,
            recentQuestionFamilies: recentQuestionFamilies
        )
    }

    func record(questionSpec: QuestionSpec) {
        append(questionSpec.conceptId, into: &recentConceptIds)
        append(hashPrompt(questionSpec.prompt), into: &recentPromptHashes)
        append(questionSpec.interactionType, into: &recentInteractionTypes)
        append(normalizedExpectedAnswer(from: questionSpec), into: &recentExpectedAnswers)
        append((questionSpec.questionFamily ?? fallbackQuestionFamily(for: questionSpec.conceptId, interactionType: questionSpec.interactionType)).lowercased(), into: &recentQuestionFamilies)
        persist()
    }

    private func append(_ value: String, into array: inout [String]) {
        guard !value.isEmpty else { return }
        array.append(value)
        if array.count > maxHistoryCount {
            array.removeFirst(array.count - maxHistoryCount)
        }
    }

    private func hashPrompt(_ prompt: String) -> String {
        let normalized = prompt
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16).lowercased()
    }


    private func fallbackQuestionFamily(for conceptId: String, interactionType: String) -> String {
        if conceptId.hasPrefix("tri.basics.") { return interactionType == "multiple_choice" ? "basics_mcq" : "basics_highlight" }
        if conceptId.hasPrefix("tri.structure.") { return interactionType == "multiple_choice" ? "structure_mcq" : "structure_identify" }
        if conceptId.hasPrefix("tri.reasoning.") { return interactionType == "numeric_input" ? "reasoning_numeric" : "reasoning_compare" }
        if conceptId.hasPrefix("tri.pyth.") { return interactionType == "numeric_input" ? "pyth_numeric" : "pyth_relation" }
        if conceptId.hasPrefix("tri.app.") { return interactionType == "numeric_input" ? "application_numeric" : "application_scenario" }
        return "generic_\(interactionType)"
    }

    private func persist() {
        let payload = snapshot()
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let payload = try? JSONDecoder().decode(LearnerContextPayload.self, from: data) else { return }
        recentConceptIds = payload.recentConceptIds
        recentPromptHashes = payload.recentPromptHashes
        recentInteractionTypes = payload.recentInteractionTypes
        recentExpectedAnswers = payload.recentExpectedAnswers
        recentQuestionFamilies = payload.recentQuestionFamilies
    }

    private func normalizedExpectedAnswer(from questionSpec: QuestionSpec) -> String {
        let normalizedKind = questionSpec.responseContract.answer.kind
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = questionSpec.responseContract.answer.value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedKind):\(normalizedValue)"
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
