import Foundation

struct CurriculumConcept: Codable, Equatable {
    let id: String
    let levelIndex: Int
    let title: String
}

struct CurriculumLevel: Codable, Equatable {
    let index: Int
    let title: String
    let conceptIDs: [String]
    let unlockThreshold: Double
}

struct CurriculumGraph: Codable, Equatable {
    let id: String
    let topic: TopicKey
    let concepts: [CurriculumConcept]
    let levels: [CurriculumLevel]

    var orderedConceptIDs: [String] {
        concepts.sorted { lhs, rhs in
            if lhs.levelIndex != rhs.levelIndex { return lhs.levelIndex < rhs.levelIndex }
            return lhs.id < rhs.id
        }.map(\.id)
    }

    func concepts(forLevel level: Int) -> [CurriculumConcept] {
        concepts.filter { $0.levelIndex == level }.sorted { $0.id < $1.id }
    }

    static let trianglesGrade6 = CurriculumGraph(
        id: SessionStorage.defaultConceptGraphID,
        topic: .geometryTriangles,
        concepts: [
            CurriculumConcept(id: "tri.basics.identify_right_angle", levelIndex: 1, title: "Identify right angle"),
            CurriculumConcept(id: "tri.basics.identify_right_triangle", levelIndex: 1, title: "Identify right-angled triangle"),
            CurriculumConcept(id: "tri.basics.vertices_sides_angles", levelIndex: 1, title: "Vertices, sides, and angles"),

            CurriculumConcept(id: "tri.structure.hypotenuse", levelIndex: 2, title: "Hypotenuse"),
            CurriculumConcept(id: "tri.structure.legs", levelIndex: 2, title: "Legs"),
            CurriculumConcept(id: "tri.structure.opposite_adjacent_relative", levelIndex: 2, title: "Opposite/Adjacent (relative)"),

            CurriculumConcept(id: "tri.reasoning.compare_side_lengths", levelIndex: 3, title: "Compare side lengths"),
            CurriculumConcept(id: "tri.reasoning.hypotenuse_longest", levelIndex: 3, title: "Hypotenuse is longest"),
            CurriculumConcept(id: "tri.reasoning.informal_side_relationships", levelIndex: 3, title: "Informal side relationships"),

            CurriculumConcept(id: "tri.pyth.check_if_right_triangle", levelIndex: 4, title: "Check if triangle is right"),
            CurriculumConcept(id: "tri.pyth.equation_a2_b2_c2", levelIndex: 4, title: "a² + b² = c²"),
            CurriculumConcept(id: "tri.pyth.solve_missing_side", levelIndex: 4, title: "Solve missing side"),
            CurriculumConcept(id: "tri.pyth.square_area_intuition", levelIndex: 4, title: "Square area intuition"),
            CurriculumConcept(id: "tri.pyth.square_numbers_refresher", levelIndex: 4, title: "Square numbers refresher"),

            CurriculumConcept(id: "tri.app.mixed_mastery_test", levelIndex: 5, title: "Mixed mastery test"),
            CurriculumConcept(id: "tri.app.real_life_modeling", levelIndex: 5, title: "Real-life modeling"),
            CurriculumConcept(id: "tri.app.word_problems", levelIndex: 5, title: "Word problems")
        ],
        levels: [
            CurriculumLevel(index: 1, title: "Triangle & Angle Basics", conceptIDs: [
                "tri.basics.identify_right_angle",
                "tri.basics.identify_right_triangle",
                "tri.basics.vertices_sides_angles"
            ], unlockThreshold: 1.0),
            CurriculumLevel(index: 2, title: "Right Triangle Structure", conceptIDs: [
                "tri.structure.hypotenuse",
                "tri.structure.legs",
                "tri.structure.opposite_adjacent_relative"
            ], unlockThreshold: 1.0),
            CurriculumLevel(index: 3, title: "Properties & Reasoning", conceptIDs: [
                "tri.reasoning.compare_side_lengths",
                "tri.reasoning.hypotenuse_longest",
                "tri.reasoning.informal_side_relationships"
            ], unlockThreshold: 1.0),
            CurriculumLevel(index: 4, title: "Pythagorean Theorem", conceptIDs: [
                "tri.pyth.check_if_right_triangle",
                "tri.pyth.equation_a2_b2_c2",
                "tri.pyth.solve_missing_side",
                "tri.pyth.square_area_intuition",
                "tri.pyth.square_numbers_refresher"
            ], unlockThreshold: 1.0),
            CurriculumLevel(index: 5, title: "Applications", conceptIDs: [
                "tri.app.mixed_mastery_test",
                "tri.app.real_life_modeling",
                "tri.app.word_problems"
            ], unlockThreshold: 1.0)
        ]
    )
}
