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
