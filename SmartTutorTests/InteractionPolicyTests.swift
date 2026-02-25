import XCTest
@testable import SmartTutor

final class InteractionPolicyTests: XCTestCase {
    func testAllowedModesForBasicsConcept() {
        let allowedModes = InteractionPolicy.allowedModes(for: "tri.basics.identify_right_angle")
        XCTAssertEqual(allowedModes, ["highlight", "multiple_choice"])
    }

    func testAllowedModesForPythagorasConceptIncludesNumericInput() {
        let allowedModes = InteractionPolicy.allowedModes(for: "tri.pyth.solve_missing_side")
        XCTAssertEqual(allowedModes, ["multiple_choice", "numeric_input"])
    }

    func testAllowedModesForUnknownConceptFallsBackToMultipleChoice() {
        let allowedModes = InteractionPolicy.allowedModes(for: "tri.unknown.concept")
        XCTAssertEqual(allowedModes, ["multiple_choice"])
    }


    func testDifficultyTargetUsesToleranceBand() {
        let target = DifficultyTarget.from(intent: .practice, difficulty: 3)
        XCTAssertEqual(target.band?.lowerBound, 2)
        XCTAssertEqual(target.band?.upperBound, 4)
    }

    func testStubProviderVariesPromptByConceptFamily() async throws {
        let provider = StubQuestionProvider()
        let structure = try await provider.generateQuestion(conceptId: "tri.structure.hypotenuse", difficulty: 2, intent: .practice)
        let pyth = try await provider.generateQuestion(conceptId: "tri.pyth.solve_missing_side", difficulty: 2, intent: .practice)

        XCTAssertNotEqual(structure.base.promptText, pyth.base.promptText)
    }

    func testGenerateQuestionPassesConceptPolicyModesToAPI() async throws {
        let apiClient = CapturingTriangleAPIClient()
        let fallbackProvider = MockFallbackQuestionProvider()
        let provider = ValidatedLLMQuestionProvider(apiClient: apiClient, fallbackProvider: fallbackProvider, maxRetries: 0)

        _ = try await provider.generateQuestion(
            conceptId: "tri.pyth.check_if_right_triangle",
            difficulty: 2,
            intent: .practice
        )

        XCTAssertEqual(apiClient.lastAllowedInteractionTypes, ["highlight", "multiple_choice", "numeric_input"])
    }
}

private final class CapturingTriangleAPIClient: TriangleAPIClient {
    var lastAllowedInteractionTypes: [String]?

    func generateQuestion(conceptId: String, grade: Int, target: DifficultyTarget, allowedInteractionTypes: [String]) async throws -> GeneratedQuestionEnvelope {
        lastAllowedInteractionTypes = allowedInteractionTypes
        throw URLError(.badServerResponse)
    }

    func rateDifficulty(questionSpec: QuestionSpec, grade: Int) async throws -> DifficultyRating {
        throw URLError(.badServerResponse)
    }
}

private struct MockFallbackQuestionProvider: TriangleQuestionProviding {
    func generateQuestion(conceptId: String, difficulty: Int, intent: LearningIntent) async throws -> TriangleResponse {
        TriangleResponse(
            bundleId: "fallback",
            base: TriangleBase(
                tutorMessages: [TriangleTutorMessage(role: "assistant", text: "Fallback")],
                diagramSpec: nil,
                answer: nil,
                conceptId: conceptId,
                difficulty: difficulty,
                intent: intent.rawValue,
                interactionType: "multiple_choice",
                responseMode: "multiple_choice",
                promptText: "Fallback"
            )
        )
    }
}
