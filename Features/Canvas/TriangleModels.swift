import Foundation

struct TriangleResponse: Codable {
    let bundleId: String
    let base: TriangleBase

    enum CodingKeys: String, CodingKey {
        case bundleId = "bundle_id"
        case base
    }
}

struct TriangleBase: Codable {
    let tutorMessages: [TriangleTutorMessage]
    let diagramSpec: TriangleDiagramSpec?
    let answer: TriangleAnswer?
    let conceptId: String?
    let difficulty: Int?
    let intent: String?

    enum CodingKeys: String, CodingKey {
        case tutorMessages = "tutor_messages"
        case diagramSpec = "diagram_spec"
        case answer
        case conceptId = "concept_id"
        case difficulty
        case intent
    }

    init(
        tutorMessages: [TriangleTutorMessage],
        diagramSpec: TriangleDiagramSpec?,
        answer: TriangleAnswer?,
        conceptId: String? = nil,
        difficulty: Int? = nil,
        intent: String? = nil
    ) {
        self.tutorMessages = tutorMessages
        self.diagramSpec = diagramSpec
        self.answer = answer
        self.conceptId = conceptId
        self.difficulty = difficulty
        self.intent = intent
    }
}

struct TriangleTutorMessage: Codable {
    let role: String
    let text: String
}

struct TriangleAnswer: Codable {
    let value: String
}

struct TriangleDiagramSpec: Codable {
    let points: [String: TrianglePoint]
    let segments: [String]
    let vertexLabels: [String: String]
    let rightAngleAt: String?

    enum CodingKeys: String, CodingKey {
        case points
        case segments
        case vertexLabels = "vertex_labels"
        case rightAngleAt = "right_angle_at"
    }
}

struct TrianglePoint: Codable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Double.self)
        let y = try container.decode(Double.self)
        self.x = x
        self.y = y
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

struct QuestionSpec: Codable {
    let schemaVersion: String
    let questionId: String
    let conceptId: String
    let grade: Int
    let interactionType: String
    let difficultyMetadata: DifficultyMetadata
    let diagramSpec: DiagramSpec
    let prompt: String
    let answer: SpecAnswer
    let hint: String
    let explanation: String
    let realWorldConnection: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case questionId = "question_id"
        case conceptId = "concept_id"
        case grade
        case interactionType = "interaction_type"
        case difficultyMetadata = "difficulty_metadata"
        case diagramSpec = "diagram_spec"
        case prompt
        case answer
        case hint
        case explanation
        case realWorldConnection = "real_world_connection"
    }
}

struct DifficultyMetadata: Codable {
    let generatorSelfRating: Int

    enum CodingKeys: String, CodingKey {
        case generatorSelfRating = "generator_self_rating"
    }
}

struct DiagramSpec: Codable {
    let type: String
    let pointsNormalized: [DiagramPoint]
    let rightAngleAt: String?

    enum CodingKeys: String, CodingKey {
        case type
        case pointsNormalized = "points_normalized"
        case rightAngleAt = "right_angle_at"
    }
}

struct DiagramPoint: Codable {
    let id: String
    let x: Double
    let y: Double
}

struct SpecAnswer: Codable {
    let kind: String
    let value: String
}

struct DifficultyRating: Codable {
    let schemaVersion: String
    let overall: Int
    let dimensions: DifficultyDimensions
    let gradeFit: GradeFit
    let flags: DifficultyFlags

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case overall
        case dimensions
        case gradeFit = "grade_fit"
        case flags
    }
}

struct DifficultyDimensions: Codable {
    let visual: Int
    let language: Int
    let reasoningSteps: Int
    let numeric: Int

    enum CodingKeys: String, CodingKey {
        case visual
        case language
        case reasoningSteps = "reasoning_steps"
        case numeric
    }
}

struct GradeFit: Codable {
    let ok: Bool
    let notes: String
}

struct DifficultyFlags: Codable {
    let containsTrig: Bool
    let containsFormalProof: Bool
    let containsSurdOrIrrationalRoot: Bool
    let outOfOntology: Bool
    let nonRenderableDiagram: Bool
    let interactionAnswerMismatch: Bool

    enum CodingKeys: String, CodingKey {
        case containsTrig = "contains_trig"
        case containsFormalProof = "contains_formal_proof"
        case containsSurdOrIrrationalRoot = "contains_surd_or_irrational_root"
        case outOfOntology = "out_of_ontology"
        case nonRenderableDiagram = "non_renderable_diagram"
        case interactionAnswerMismatch = "interaction_answer_mismatch"
    }
}
