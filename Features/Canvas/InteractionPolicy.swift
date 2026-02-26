import Foundation

enum InteractionPolicy {
    private static let conceptToAllowedModes: [String: [String]] = {
        var map: [String: [String]] = [:]

        let basicsAndReasoningModes = ["highlight", "multiple_choice"]
        for conceptID in CurriculumGraph.trianglesGrade6.concepts where conceptID.id.hasPrefix("tri.basics.") || conceptID.id.hasPrefix("tri.structure.") || conceptID.id.hasPrefix("tri.reasoning.") {
            map[conceptID.id] = basicsAndReasoningModes
        }

        map["tri.pyth.check_if_right_triangle"] = ["highlight", "multiple_choice", "numeric_input"]
        map["tri.pyth.equation_a2_b2_c2"] = ["multiple_choice", "numeric_input"]
        map["tri.pyth.solve_missing_side"] = ["multiple_choice", "numeric_input"]
        map["tri.pyth.square_area_intuition"] = ["highlight", "multiple_choice", "numeric_input"]
        map["tri.pyth.square_numbers_refresher"] = ["multiple_choice", "numeric_input"]

        map["tri.app.mixed_mastery_test"] = ["multiple_choice", "numeric_input"]
        map["tri.app.real_life_modeling"] = ["multiple_choice", "numeric_input"]
        map["tri.app.word_problems"] = ["multiple_choice", "numeric_input"]

        return map
    }()

    static func allowedModes(for conceptId: String) -> [String] {
        conceptToAllowedModes[conceptId] ?? ["multiple_choice"]
    }
}
