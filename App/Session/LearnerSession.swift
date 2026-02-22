import Foundation

enum GradeLevel: String, Codable, CaseIterable {
    case grade6

    var displayName: String {
        switch self {
        case .grade6: return "Grade 6"
        }
    }
}

enum SubjectDomain: String, Codable {
    case geometry
}

enum TopicKey: String, Codable {
    case geometryTriangles

    var displayName: String {
        switch self {
        case .geometryTriangles: return "Geometry → Triangles"
        }
    }
}

struct LearnerProfile: Codable, Equatable {
    let grade: GradeLevel
}

struct CurriculumSelection: Codable, Equatable {
    let subject: SubjectDomain
    let topic: TopicKey
}

struct ConceptMastery: Codable, Equatable {
    var correctCount: Int
    var currentDifficulty: Int
    var mastered: Bool
}

struct DifficultyCeiling: Codable, Equatable {
    let maxLevel: Int
}

struct ProgressionState: Codable, Equatable {
    let conceptGraphId: String
    var masteryByConcept: [String: ConceptMastery]
    var currentConceptId: String?
    let difficultyCeiling: DifficultyCeiling
}

struct SessionMeta: Codable, Equatable {
    let schemaVersion: Int
    let createdAtISO8601: String
    var lastOpenedAtISO8601: String
}

struct LearnerSession: Codable, Equatable {
    var learner: LearnerProfile
    var curriculum: CurriculumSelection
    var progression: ProgressionState
    var sessionMeta: SessionMeta
}
