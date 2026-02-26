import Foundation

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
        let allowedTypes = InteractionPolicy.allowedModes(for: conceptId)
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
        print("[M3Pipeline] request=\(entry.requestId) concept=\(entry.conceptId) attempt=\(entry.attempt) accepted=\(entry.accepted) reason=\(entry.reason) rated=\(entry.ratedOverall.map(String.init) ?? "n/a") fallback=\(entry.fallbackUsed)")
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
                answer: TriangleAnswer(value: spec.responseContract.answer.value),
                conceptId: spec.conceptId,
                difficulty: ratedDifficulty,
                intent: intent.rawValue,
                interactionType: spec.interactionType,
                responseMode: spec.responseContract.mode,
                promptText: spec.prompt,
                responseContract: spec.responseContract,
                assessmentContract: spec.assessmentContract
            )
        )
    }
}

enum QuestionSpecValidator {
    private struct ConceptSemanticRule {
        let requiredSignalGroups: [[String]]
        let forbiddenSignals: [String]
    }

    private static let conceptSemanticRules: [String: ConceptSemanticRule] = [
        "tri.basics.identify_right_angle": ConceptSemanticRule(
            requiredSignalGroups: [["right angle", "90"]],
            forbiddenSignals: ["hypotenuse", "a2+b2", "a²+b²", "pythag"]
        ),
        "tri.basics.identify_right_triangle": ConceptSemanticRule(
            requiredSignalGroups: [["right triangle", "right-angled triangle", "right angle"]],
            forbiddenSignals: ["a2+b2", "a²+b²", "pythag"]
        ),
        "tri.basics.vertices_sides_angles": ConceptSemanticRule(
            requiredSignalGroups: [["vertex", "vertices"], ["side"], ["angle"]],
            forbiddenSignals: ["a2+b2", "a²+b²", "pythag"]
        ),
        "tri.structure.hypotenuse": ConceptSemanticRule(
            requiredSignalGroups: [["hypotenuse"], ["right angle", "right triangle"]],
            forbiddenSignals: ["a2+b2", "a²+b²", "pythag"]
        ),
        "tri.structure.legs": ConceptSemanticRule(
            requiredSignalGroups: [["leg", "legs"]],
            forbiddenSignals: ["hypotenuse only", "a2+b2", "a²+b²"]
        ),
        "tri.structure.opposite_adjacent_relative": ConceptSemanticRule(
            requiredSignalGroups: [["opposite"], ["adjacent"]],
            forbiddenSignals: ["sin", "cos", "tan"]
        ),
        "tri.reasoning.compare_side_lengths": ConceptSemanticRule(
            requiredSignalGroups: [["compare", "order", "longer", "shorter"], ["side", "length"]],
            forbiddenSignals: ["sin", "cos", "tan"]
        ),
        "tri.reasoning.hypotenuse_longest": ConceptSemanticRule(
            requiredSignalGroups: [["hypotenuse"], ["longest"]],
            forbiddenSignals: ["a2+b2", "a²+b²", "pythag"]
        ),
        "tri.reasoning.informal_side_relationships": ConceptSemanticRule(
            requiredSignalGroups: [["side relationship", "statement", "always", "sometimes", "never"]],
            forbiddenSignals: ["formal proof", "sin", "cos", "tan"]
        ),
        "tri.pyth.check_if_right_triangle": ConceptSemanticRule(
            requiredSignalGroups: [["right triangle", "right-angle triangle"], ["a2+b2", "a²+b²", "pythag"]],
            forbiddenSignals: ["sin", "cos", "tan"]
        ),
        "tri.pyth.equation_a2_b2_c2": ConceptSemanticRule(
            requiredSignalGroups: [["a2+b2", "a²+b²", "c2", "c²", "pythag"]],
            forbiddenSignals: ["sin", "cos", "tan"]
        ),
        "tri.pyth.solve_missing_side": ConceptSemanticRule(
            requiredSignalGroups: [["missing side", "unknown side", "find side", "solve"], ["a2+b2", "a²+b²", "pythag"]],
            forbiddenSignals: ["sin", "cos", "tan"]
        ),
        "tri.pyth.square_area_intuition": ConceptSemanticRule(
            requiredSignalGroups: [["square", "area"], ["a2+b2", "a²+b²", "c2", "c²"]],
            forbiddenSignals: ["sin", "cos", "tan"]
        ),
        "tri.pyth.square_numbers_refresher": ConceptSemanticRule(
            requiredSignalGroups: [["square number", "squared", "perfect square"]],
            forbiddenSignals: ["sin", "cos", "tan"]
        ),
        "tri.app.mixed_mastery_test": ConceptSemanticRule(
            requiredSignalGroups: [["mixed", "review", "mastery"], ["triangle", "right triangle"]],
            forbiddenSignals: ["sin", "cos", "tan"]
        ),
        "tri.app.real_life_modeling": ConceptSemanticRule(
            requiredSignalGroups: [["real-life", "model", "ramp", "ladder", "roof"]],
            forbiddenSignals: ["sin", "cos", "tan"]
        ),
        "tri.app.word_problems": ConceptSemanticRule(
            requiredSignalGroups: [["word problem", "story", "situation"], ["triangle", "right triangle"]],
            forbiddenSignals: ["sin", "cos", "tan"]
        )
    ]

    static func validate(question: QuestionSpec, conceptId: String, allowedInteractionTypes: [String]) throws {
        guard question.schemaVersion == "m3.question_spec.v2" else { throw ValidationError.schema }
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

        guard question.responseContract.mode == question.interactionType else { throw ValidationError.answerMismatch }

        switch question.interactionType {
        case "highlight":
            guard question.responseContract.answer.kind == "point_set" || question.responseContract.answer.kind == "segment" else { throw ValidationError.answerMismatch }
        case "multiple_choice":
            guard question.responseContract.answer.kind == "option_id" else { throw ValidationError.answerMismatch }
            guard let options = question.responseContract.options, options.count >= 2 else { throw ValidationError.answerMismatch }
            guard options.contains(where: { $0.id == question.responseContract.answer.value }) else { throw ValidationError.answerMismatch }
        case "numeric_input":
            guard question.responseContract.answer.kind == "number" else { throw ValidationError.answerMismatch }
            guard Double(question.responseContract.answer.value) != nil else { throw ValidationError.answerMismatch }
        default:
            throw ValidationError.interaction
        }

        guard let assessmentContract = question.assessmentContract else { throw ValidationError.assessmentContract }
        guard !assessmentContract.objectiveType.isEmpty, !assessmentContract.answerSchema.isEmpty, !assessmentContract.gradingStrategyId.isEmpty, !assessmentContract.feedbackPolicyId.isEmpty else {
            throw ValidationError.assessmentContract
        }

        try validateConceptSemantics(question)
    }

    private static func validateConceptSemantics(_ question: QuestionSpec) throws {
        let textPool = buildSemanticTextPool(question)
        if let rule = conceptSemanticRules[question.conceptId] {
            let missingRequired = rule.requiredSignalGroups.contains { group in
                !group.contains { signal in textPool.contains(normalizeSignal(signal)) }
            }
            let hasForbidden = rule.forbiddenSignals.contains { signal in
                textPool.contains(normalizeSignal(signal))
            }
            if missingRequired || hasForbidden {
                throw ValidationError.conceptMismatch
            }
        }

        if isGenericRepetition(question) {
            throw ValidationError.genericRepetition
        }
    }

    nonisolated private static func buildSemanticTextPool(_ question: QuestionSpec) -> String {
        let optionsText = question.responseContract.options?.map(\.text).joined(separator: " ") ?? ""
        return normalizeSignal([
            question.prompt,
            question.hint,
            question.explanation,
            question.realWorldConnection,
            question.responseContract.answer.value,
            optionsText
        ].joined(separator: " "))
    }

    nonisolated private static func normalizeSignal(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9²+ ]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func isGenericRepetition(_ question: QuestionSpec) -> Bool {
        let normalizedBlocks = [question.prompt, question.hint, question.explanation].map(normalizeSignal)
        let uniqueBlocks = Set(normalizedBlocks.filter { !$0.isEmpty })
        if uniqueBlocks.count <= 1 {
            return true
        }

        let words = normalizedBlocks
            .joined(separator: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 }
        return Set(words).count < 8
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
    case conceptMismatch
    case genericRepetition
    case assessmentContract
}
