import Foundation

protocol TriangleQuestionProviding {
    func generateQuestion(conceptId: String, difficulty: Int, intent: LearningIntent) async throws -> TriangleResponse
}

struct StubQuestionProvider: TriangleQuestionProviding {
    func generateQuestion(conceptId: String, difficulty: Int, intent: LearningIntent) async throws -> TriangleResponse {
        let cappedDifficulty = min(max(difficulty, 1), SessionStorage.grade6DifficultyCeiling)
        let interactionType = defaultInteractionType(for: conceptId)
        let template = templateForConcept(conceptId: conceptId, interactionType: interactionType)

        return TriangleResponse(
            bundleId: "stub.\(conceptId).d\(cappedDifficulty).\(intent.rawValue)",
            base: TriangleBase(
                tutorMessages: [
                    TriangleTutorMessage(role: "assistant", text: template.prompt),
                    TriangleTutorMessage(role: "assistant", text: template.hint),
                    TriangleTutorMessage(role: "assistant", text: template.realWorld)
                ],
                diagramSpec: TriangleDiagramSpec(
                    points: [
                        "A": TrianglePoint(x: 0.2, y: 0.78),
                        "B": TrianglePoint(x: 0.8, y: 0.78),
                        "C": TrianglePoint(x: 0.55, y: 0.18)
                    ],
                    segments: ["AB", "BC", "CA"],
                    vertexLabels: ["A": "A", "B": "B", "C": "C"],
                    rightAngleAt: "C"
                ),
                answer: TriangleAnswer(value: template.answer),
                conceptId: conceptId,
                difficulty: cappedDifficulty,
                intent: intent.rawValue,
                interactionType: interactionType,
                responseMode: interactionType,
                promptText: template.prompt,
                responseContract: responseContract(for: interactionType, answer: template.answer)
            )
        )
    }


    private func defaultInteractionType(for conceptId: String) -> String {
        if conceptId.hasPrefix("tri.pyth.") || conceptId.hasPrefix("tri.app.") {
            return "multiple_choice"
        }
        if conceptId.hasPrefix("tri.basics.") || conceptId.hasPrefix("tri.structure.") || conceptId.hasPrefix("tri.reasoning.") {
            return "highlight"
        }
        return "multiple_choice"
    }

    private func templateForConcept(conceptId: String, interactionType: String) -> (prompt: String, hint: String, realWorld: String, answer: String) {
        if conceptId.hasPrefix("tri.basics.") {
            return (
                interactionType == "highlight" ? "Highlight the right-angle vertex." : "Which option names the right-angle vertex?",
                "Look for the tiny square that marks 90°.",
                "Carpenters use right angles to make square corners.",
                interactionType == "multiple_choice" ? "opt_c" : "C"
            )
        }
        if conceptId.hasPrefix("tri.structure.") {
            return (
                interactionType == "highlight" ? "Highlight the hypotenuse." : "Which side is the hypotenuse?",
                "The hypotenuse is opposite the right angle.",
                "Ramp length is often the hypotenuse in real life.",
                interactionType == "multiple_choice" ? "opt_ab" : "AB"
            )
        }
        if conceptId.hasPrefix("tri.reasoning.") {
            if interactionType == "numeric_input" {
                return (
                    "Enter the longest side length for a 6-8-10 right triangle.",
                    "The side opposite 90° is longest.",
                    "Designers compare side lengths when planning supports.",
                    "10"
                )
            }
            return (
                "Which side should be longest in this right triangle?",
                "Use the right-angle marker to identify side roles.",
                "Ladders and braces use this longest-side rule.",
                "opt_ab"
            )
        }
        if conceptId.hasPrefix("tri.pyth.") {
            if interactionType == "numeric_input" {
                return (
                    "A right triangle has legs 5 and 12. Enter the hypotenuse length.",
                    "Use a² + b² = c².",
                    "This helps estimate diagonal distances safely.",
                    "13"
                )
            }
            return (
                "Which equation shows the Pythagorean relationship?",
                "Think: square of hypotenuse equals sum of leg squares.",
                "Architects use this check for right-angle layouts.",
                "opt_a"
            )
        }
        if interactionType == "numeric_input" {
            return (
                "A ladder is 13 m long and reaches 12 m high. Enter the base distance from wall.",
                "Model the story as a right triangle first.",
                "Emergency ladders rely on this triangle model.",
                "5"
            )
        }
        return (
            "A ladder, wall, and ground form a triangle. Which side is the hypotenuse?",
            "The hypotenuse is opposite the right angle.",
            "This model appears in construction and rescue planning.",
            "opt_ab"
        )
    }

    private func responseContract(for interactionType: String, answer: String) -> ResponseContract {
        switch interactionType {
        case "highlight":
            return ResponseContract(mode: "highlight", answer: SpecAnswer(kind: "point_set", value: answer), options: nil, numericRule: nil)
        case "numeric_input":
            return ResponseContract(mode: "numeric_input", answer: SpecAnswer(kind: "number", value: answer), options: nil, numericRule: NumericRule(tolerance: 0))
        default:
            return ResponseContract(
                mode: "multiple_choice",
                answer: SpecAnswer(kind: "option_id", value: answer),
                options: [
                    ResponseOption(id: "opt_a", text: "a² + b² = c²"),
                    ResponseOption(id: "opt_b", text: "a + b = c"),
                    ResponseOption(id: "opt_c", text: "Right angle at C"),
                    ResponseOption(id: "opt_ab", text: "AB")
                ],
                numericRule: nil
            )
        }
    }
}
