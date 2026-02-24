import Foundation

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
        return DifficultyTarget(band: clamped...clamped, direction: direction)
    }
}

enum DifficultyDirection: String, Codable {
    case easier
    case same
    case harder
}

struct QuestionPipelineTelemetry {
    let requestId: String
    let conceptId: String
    let attempt: Int
    let accepted: Bool
    let reason: String
    let ratedOverall: Int?
    let fallbackUsed: Bool
}

struct ValidatedLLMQuestionProvider: TriangleQuestionProviding {
    private let apiClient: TriangleAPIClient
    private let fallbackProvider: TriangleQuestionProviding
    private let maxRetries: Int

    init(apiClient: TriangleAPIClient = LiveTriangleAPIClient(), fallbackProvider: TriangleQuestionProviding = StubQuestionProvider(), maxRetries: Int = 2) {
        self.apiClient = apiClient
        self.fallbackProvider = fallbackProvider
        self.maxRetries = maxRetries
    }

    func generateQuestion(conceptId: String, difficulty: Int, intent: LearningIntent) async throws -> TriangleResponse {
        let target = DifficultyTarget.from(intent: intent, difficulty: difficulty)
        let allowedTypes = InteractionPolicy.allowedTypes(for: conceptId)
        let requestId = UUID().uuidString

        for attempt in 0...maxRetries {
            do {
                let generated = try await apiClient.generateQuestion(
                    conceptId: conceptId,
                    grade: 6,
                    target: target,
                    allowedInteractionTypes: allowedTypes
                )

                try QuestionSpecValidator.validate(question: generated.questionSpec, conceptId: conceptId, allowedInteractionTypes: allowedTypes)

                let rating = try await apiClient.rateDifficulty(questionSpec: generated.questionSpec, grade: 6)
                try DifficultyRatingValidator.validate(rating: rating)

                if shouldAccept(rating: rating, target: target, requestedDifficulty: difficulty) {
                    logTelemetry(QuestionPipelineTelemetry(
                        requestId: requestId,
                        conceptId: conceptId,
                        attempt: attempt,
                        accepted: true,
                        reason: "accepted",
                        ratedOverall: rating.overall,
                        fallbackUsed: false
                    ))
                    return TriangleAdapter.triangleResponse(from: generated.questionSpec, ratedDifficulty: rating.overall, intent: intent)
                }

                logTelemetry(QuestionPipelineTelemetry(
                    requestId: requestId,
                    conceptId: conceptId,
                    attempt: attempt,
                    accepted: false,
                    reason: "difficulty_miss",
                    ratedOverall: rating.overall,
                    fallbackUsed: false
                ))
            } catch {
                logTelemetry(QuestionPipelineTelemetry(
                    requestId: requestId,
                    conceptId: conceptId,
                    attempt: attempt,
                    accepted: false,
                    reason: String(describing: error),
                    ratedOverall: nil,
                    fallbackUsed: false
                ))
            }
        }

        logTelemetry(QuestionPipelineTelemetry(
            requestId: requestId,
            conceptId: conceptId,
            attempt: maxRetries,
            accepted: false,
            reason: "fallback",
            ratedOverall: nil,
            fallbackUsed: true
        ))

        return try await fallbackProvider.generateQuestion(conceptId: conceptId, difficulty: difficulty, intent: intent)
    }

    private func shouldAccept(rating: DifficultyRating, target: DifficultyTarget, requestedDifficulty: Int) -> Bool {
        guard rating.gradeFit.ok else { return false }
        if rating.flags.containsTrig || rating.flags.containsFormalProof || rating.flags.containsSurdOrIrrationalRoot || rating.flags.outOfOntology || rating.flags.nonRenderableDiagram || rating.flags.interactionAnswerMismatch {
            return false
        }
        if let band = target.band {
            return band.contains(rating.overall)
        }
        guard let direction = target.direction else {
            return rating.overall == requestedDifficulty
        }
        switch direction {
        case .easier:
            return rating.overall < requestedDifficulty
        case .same:
            return rating.overall == requestedDifficulty
        case .harder:
            return rating.overall > requestedDifficulty
        }
    }

    private func logTelemetry(_ entry: QuestionPipelineTelemetry) {
        print("[M3Pipeline] request=\(entry.requestId) concept=\(entry.conceptId) attempt=\(entry.attempt) accepted=\(entry.accepted) reason=\(entry.reason) rated=\(entry.ratedOverall.map(String.init) ?? \"n/a\") fallback=\(entry.fallbackUsed)")
    }
}

enum InteractionPolicy {
    static func allowedTypes(for conceptId: String) -> [String] {
        if conceptId.contains("pyth") {
            return ["numeric_input", "multiple_choice", "highlight"]
        }
        if conceptId.contains("app") {
            return ["multiple_choice", "numeric_input", "highlight"]
        }
        return ["highlight", "multiple_choice"]
    }
}

enum TriangleAdapter {
    static func triangleResponse(from spec: QuestionSpec, ratedDifficulty: Int, intent: LearningIntent) -> TriangleResponse {
        let points = Dictionary(uniqueKeysWithValues: spec.diagramSpec.pointsNormalized.map { point in
            (point.id, TrianglePoint(x: point.x, y: point.y))
        })

        let segments = ["AB", "BC", "CA"]
        let labels = Dictionary(uniqueKeysWithValues: spec.diagramSpec.pointsNormalized.map { ($0.id, $0.id) })

        return TriangleResponse(
            bundleId: spec.questionId,
            base: TriangleBase(
                tutorMessages: [
                    TriangleTutorMessage(role: "assistant", text: spec.prompt),
                    TriangleTutorMessage(role: "assistant", text: spec.hint),
                    TriangleTutorMessage(role: "assistant", text: spec.realWorldConnection)
                ],
                diagramSpec: TriangleDiagramSpec(
                    points: points,
                    segments: segments,
                    vertexLabels: labels,
                    rightAngleAt: spec.diagramSpec.rightAngleAt
                ),
                answer: TriangleAnswer(value: spec.answer.value),
                conceptId: spec.conceptId,
                difficulty: ratedDifficulty,
                intent: intent.rawValue
            )
        )
    }
}

enum QuestionSpecValidator {
    static func validate(question: QuestionSpec, conceptId: String, allowedInteractionTypes: [String]) throws {
        guard question.schemaVersion == "m3.question_spec.v1" else { throw ValidationError.schema }
        guard question.grade == 6 else { throw ValidationError.gradeCap }
        guard question.conceptId == conceptId else { throw ValidationError.ontology }
        guard CurriculumGraph.trianglesGrade6.concepts.contains(where: { $0.id == conceptId }) else { throw ValidationError.ontology }
        guard allowedInteractionTypes.contains(question.interactionType) else { throw ValidationError.interaction }

        let normalizedText = [question.prompt, question.hint, question.explanation, question.realWorldConnection].joined(separator: " ").lowercased()
        if normalizedText.contains("sin") || normalizedText.contains("cos") || normalizedText.contains("tan") {
            throw ValidationError.gradeCap
        }
        if normalizedText.contains("proof") || normalizedText.contains("surd") || normalizedText.contains("irrational") {
            throw ValidationError.gradeCap
        }

        guard question.diagramSpec.type == "triangle" else { throw ValidationError.renderability }
        guard question.diagramSpec.pointsNormalized.count == 3 else { throw ValidationError.renderability }
        let ids = Set(question.diagramSpec.pointsNormalized.map(\.id))
        guard ids == Set(["A", "B", "C"]) else { throw ValidationError.renderability }
        guard question.diagramSpec.pointsNormalized.allSatisfy({ $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 }) else {
            throw ValidationError.renderability
        }

        guard triangleArea(from: question.diagramSpec.pointsNormalized) > 0.001 else { throw ValidationError.renderability }

        switch question.interactionType {
        case "highlight":
            guard question.answer.kind == "point_set" || question.answer.kind == "segment" else { throw ValidationError.answerMismatch }
        case "multiple_choice":
            guard question.answer.kind == "option_id" else { throw ValidationError.answerMismatch }
        case "numeric_input":
            guard question.answer.kind == "number" else { throw ValidationError.answerMismatch }
            guard Double(question.answer.value) != nil else { throw ValidationError.answerMismatch }
        default:
            throw ValidationError.interaction
        }
    }

    private static func triangleArea(from points: [DiagramPoint]) -> Double {
        guard
            let a = points.first(where: { $0.id == "A" }),
            let b = points.first(where: { $0.id == "B" }),
            let c = points.first(where: { $0.id == "C" })
        else { return 0 }

        return abs(a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y)) / 2
    }
}

enum DifficultyRatingValidator {
    static func validate(rating: DifficultyRating) throws {
        guard rating.schemaVersion == "m3.difficulty_rating.v1" else { throw ValidationError.schema }
        guard (1...4).contains(rating.overall) else { throw ValidationError.schema }
        guard (1...4).contains(rating.dimensions.visual), (1...4).contains(rating.dimensions.language), (1...4).contains(rating.dimensions.reasoningSteps), (1...4).contains(rating.dimensions.numeric) else {
            throw ValidationError.schema
        }
    }
}

enum ValidationError: Error {
    case schema
    case ontology
    case interaction
    case gradeCap
    case renderability
    case answerMismatch
}
