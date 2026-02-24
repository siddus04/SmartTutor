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
    var attemptCount: Int
    var incorrectCount: Int
    var highestDifficultyPassed: Int
    var needsRemediation: Bool
    var lastOutcome: LastMasteryOutcome

    init(
        correctCount: Int,
        currentDifficulty: Int,
        mastered: Bool,
        attemptCount: Int = 0,
        incorrectCount: Int = 0,
        highestDifficultyPassed: Int = 0,
        needsRemediation: Bool = false,
        lastOutcome: LastMasteryOutcome = .none
    ) {
        self.correctCount = correctCount
        self.currentDifficulty = currentDifficulty
        self.mastered = mastered
        self.attemptCount = attemptCount
        self.incorrectCount = incorrectCount
        self.highestDifficultyPassed = highestDifficultyPassed
        self.needsRemediation = needsRemediation
        self.lastOutcome = lastOutcome
    }

    enum CodingKeys: String, CodingKey {
        case correctCount
        case currentDifficulty
        case mastered
        case attemptCount
        case incorrectCount
        case highestDifficultyPassed
        case needsRemediation
        case lastOutcome
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        correctCount = try c.decode(Int.self, forKey: .correctCount)
        currentDifficulty = try c.decode(Int.self, forKey: .currentDifficulty)
        mastered = try c.decode(Bool.self, forKey: .mastered)
        attemptCount = try c.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        incorrectCount = try c.decodeIfPresent(Int.self, forKey: .incorrectCount) ?? 0
        highestDifficultyPassed = try c.decodeIfPresent(Int.self, forKey: .highestDifficultyPassed) ?? 0
        needsRemediation = try c.decodeIfPresent(Bool.self, forKey: .needsRemediation) ?? false
        lastOutcome = try c.decodeIfPresent(LastMasteryOutcome.self, forKey: .lastOutcome) ?? .none
    }
}

struct DifficultyCeiling: Codable, Equatable {
    let maxLevel: Int
}

struct ProgressionState: Codable, Equatable {
    let conceptGraphId: String
    var masteryByConcept: [String: ConceptMastery]
    var currentConceptId: String?
    let difficultyCeiling: DifficultyCeiling
    var unlockedLevelIndices: [Int]
    var topicCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case conceptGraphId
        case masteryByConcept
        case currentConceptId
        case difficultyCeiling
        case unlockedLevelIndices
        case topicCompleted
    }

    init(
        conceptGraphId: String,
        masteryByConcept: [String: ConceptMastery],
        currentConceptId: String?,
        difficultyCeiling: DifficultyCeiling,
        unlockedLevelIndices: [Int] = [1],
        topicCompleted: Bool = false
    ) {
        self.conceptGraphId = conceptGraphId
        self.masteryByConcept = masteryByConcept
        self.currentConceptId = currentConceptId
        self.difficultyCeiling = difficultyCeiling
        self.unlockedLevelIndices = unlockedLevelIndices
        self.topicCompleted = topicCompleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        conceptGraphId = try c.decode(String.self, forKey: .conceptGraphId)
        masteryByConcept = try c.decode([String: ConceptMastery].self, forKey: .masteryByConcept)
        currentConceptId = try c.decodeIfPresent(String.self, forKey: .currentConceptId)
        difficultyCeiling = try c.decode(DifficultyCeiling.self, forKey: .difficultyCeiling)
        unlockedLevelIndices = try c.decodeIfPresent([Int].self, forKey: .unlockedLevelIndices) ?? [1]
        topicCompleted = try c.decodeIfPresent(Bool.self, forKey: .topicCompleted) ?? false
    }
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
