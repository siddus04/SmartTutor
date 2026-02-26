import XCTest
@testable import SmartTutor

final class M3ValidationTests: XCTestCase {
    func testQuestionSpecValidatorRejectsOutOfOntologyConcept() throws {
        var spec = makeValidQuestionSpec()
        spec = QuestionSpec(
            schemaVersion: spec.schemaVersion,
            questionId: spec.questionId,
            conceptId: "tri.outside.ontology",
            grade: spec.grade,
            interactionType: spec.interactionType,
            difficultyMetadata: spec.difficultyMetadata,
            diagramSpec: spec.diagramSpec,
            prompt: spec.prompt,
            assessmentContract: spec.assessmentContract,
            responseContract: spec.responseContract,
            hint: spec.hint,
            explanation: spec.explanation,
            realWorldConnection: spec.realWorldConnection
        )

        XCTAssertThrowsError(try QuestionSpecValidator.validate(question: spec, conceptId: spec.conceptId, allowedInteractionTypes: ["highlight"]))
    }

    func testQuestionSpecValidatorRejectsAnswerMismatch() throws {
        var spec = makeValidQuestionSpec()
        spec = QuestionSpec(
            schemaVersion: spec.schemaVersion,
            questionId: spec.questionId,
            conceptId: spec.conceptId,
            grade: spec.grade,
            interactionType: "numeric_input",
            difficultyMetadata: spec.difficultyMetadata,
            diagramSpec: spec.diagramSpec,
            prompt: spec.prompt,
            assessmentContract: AssessmentContract(
                schemaVersion: "m3.assessment_contract.v1",
                conceptId: spec.conceptId,
                interactionType: "numeric_input",
                objectiveType: "compute_value",
                answerSchema: "numeric_with_tolerance",
                gradingStrategyId: "deterministic_rule",
                feedbackPolicyId: "hint_progressive_reveal_level_1",
                expectedAnswer: SpecAnswer(kind: "option_id", value: "A"),
                options: nil,
                numericRule: nil
            ),
            responseContract: ResponseContract(
                mode: "numeric_input",
                answer: SpecAnswer(kind: "option_id", value: "A"),
                options: nil,
                numericRule: nil
            ),
            hint: spec.hint,
            explanation: spec.explanation,
            realWorldConnection: spec.realWorldConnection
        )

        XCTAssertThrowsError(try QuestionSpecValidator.validate(question: spec, conceptId: spec.conceptId, allowedInteractionTypes: ["numeric_input"]))
    }


    func testQuestionSpecValidatorRejectsConceptMismatch() throws {
        var spec = makeValidQuestionSpec()
        spec = QuestionSpec(
            schemaVersion: spec.schemaVersion,
            questionId: spec.questionId,
            conceptId: spec.conceptId,
            grade: spec.grade,
            interactionType: spec.interactionType,
            difficultyMetadata: spec.difficultyMetadata,
            diagramSpec: spec.diagramSpec,
            prompt: "Tap the longest side in this triangle.",
            assessmentContract: spec.assessmentContract,
            responseContract: spec.responseContract,
            hint: "The longest side is opposite the biggest angle.",
            explanation: "Use side-length reasoning to identify the longest side.",
            realWorldConnection: spec.realWorldConnection
        )

        XCTAssertThrowsError(try QuestionSpecValidator.validate(question: spec, conceptId: spec.conceptId, allowedInteractionTypes: ["highlight"])) { error in
            guard case ValidationError.conceptMismatch = error else {
                return XCTFail("Expected conceptMismatch, got \(error)")
            }
        }
    }

    func testQuestionSpecValidatorRejectsGenericRepetition() throws {
        var spec = makeValidQuestionSpec()
        spec = QuestionSpec(
            schemaVersion: spec.schemaVersion,
            questionId: spec.questionId,
            conceptId: spec.conceptId,
            grade: spec.grade,
            interactionType: spec.interactionType,
            difficultyMetadata: spec.difficultyMetadata,
            diagramSpec: spec.diagramSpec,
            prompt: "Pick AB.",
            assessmentContract: spec.assessmentContract,
            responseContract: spec.responseContract,
            hint: "Pick AB.",
            explanation: "Pick AB.",
            realWorldConnection: spec.realWorldConnection
        )

        XCTAssertThrowsError(try QuestionSpecValidator.validate(question: spec, conceptId: spec.conceptId, allowedInteractionTypes: ["highlight"])) { error in
            guard case ValidationError.genericRepetition = error else {
                return XCTFail("Expected genericRepetition, got \(error)")
            }
        }
    }

    func testDifficultyRatingValidatorAcceptsRange() throws {
        let rating = DifficultyRating(
            schemaVersion: "m3.difficulty_rating.v1",
            overall: 2,
            dimensions: DifficultyDimensions(visual: 2, language: 2, reasoningSteps: 2, numeric: 1),
            gradeFit: GradeFit(ok: true, notes: "ok"),
            flags: DifficultyFlags(
                containsTrig: false,
                containsFormalProof: false,
                containsSurdOrIrrationalRoot: false,
                outOfOntology: false,
                nonRenderableDiagram: false,
                interactionAnswerMismatch: false
            )
        )
        XCTAssertNoThrow(try DifficultyRatingValidator.validate(rating: rating))
    }

    private func makeValidQuestionSpec() -> QuestionSpec {
        QuestionSpec(
            schemaVersion: "m3.question_spec.v2",
            questionId: "q1",
            conceptId: "tri.structure.hypotenuse",
            grade: 6,
            interactionType: "highlight",
            difficultyMetadata: DifficultyMetadata(generatorSelfRating: 2),
            diagramSpec: DiagramSpec(
                type: "triangle",
                pointsNormalized: [
                    DiagramPoint(id: "A", x: 0.2, y: 0.8),
                    DiagramPoint(id: "B", x: 0.8, y: 0.8),
                    DiagramPoint(id: "C", x: 0.5, y: 0.2)
                ],
                rightAngleAt: "C"
            ),
            prompt: "Circle the hypotenuse.",
            assessmentContract: AssessmentContract(
                schemaVersion: "m3.assessment_contract.v1",
                conceptId: "tri.structure.hypotenuse",
                interactionType: "highlight",
                objectiveType: "identify_segment",
                answerSchema: "segment_set",
                gradingStrategyId: "vision_locator",
                feedbackPolicyId: "hint_progressive_reveal_level_1",
                expectedAnswer: SpecAnswer(kind: "segment", value: "AB"),
                options: nil,
                numericRule: nil
            ),
            responseContract: ResponseContract(
                mode: "highlight",
                answer: SpecAnswer(kind: "segment", value: "AB"),
                options: nil,
                numericRule: nil
            ),
            hint: "Opposite the right angle.",
            explanation: "The hypotenuse is across from the right angle.",
            realWorldConnection: "Think of a ladder on a wall."
        )
    }
}
