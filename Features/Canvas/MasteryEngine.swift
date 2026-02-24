import Foundation

enum LearningIntent: String, Codable {
    case teach
    case practice
    case remediate
    case assess
}

enum MasteryOutcome {
    case correct
    case incorrect
    case ambiguous
}

enum LastMasteryOutcome: String, Codable {
    case correct
    case incorrect
    case ambiguous
    case none
}

struct LearningStep: Equatable {
    let conceptId: String?
    let difficulty: Int?
    let intent: LearningIntent
    let isComplete: Bool

    static func completed() -> LearningStep {
        LearningStep(conceptId: nil, difficulty: nil, intent: .assess, isComplete: true)
    }
}

enum MasteryEngine {
    static func bootstrapProgression(graph: CurriculumGraph, ceiling: Int) -> ProgressionState {
        var mastery: [String: ConceptMastery] = [:]
        for concept in graph.concepts {
            mastery[concept.id] = ConceptMastery(
                correctCount: 0,
                currentDifficulty: 1,
                mastered: false,
                attemptCount: 0,
                incorrectCount: 0,
                highestDifficultyPassed: 0,
                needsRemediation: false,
                lastOutcome: .none
            )
        }

        return ProgressionState(
            conceptGraphId: graph.id,
            masteryByConcept: mastery,
            currentConceptId: graph.levels.first?.conceptIDs.first,
            difficultyCeiling: DifficultyCeiling(maxLevel: ceiling),
            unlockedLevelIndices: [1],
            topicCompleted: false
        )
    }

    static func nextLearningStep(state: ProgressionState, graph: CurriculumGraph) -> LearningStep {
        if state.topicCompleted { return .completed() }

        for level in graph.levels where state.unlockedLevelIndices.contains(level.index) {
            for conceptId in level.conceptIDs {
                guard let mastery = state.masteryByConcept[conceptId], !mastery.mastered else { continue }
                if mastery.needsRemediation {
                    return LearningStep(conceptId: conceptId, difficulty: mastery.currentDifficulty, intent: .remediate, isComplete: false)
                }
                return LearningStep(conceptId: conceptId, difficulty: mastery.currentDifficulty, intent: .practice, isComplete: false)
            }
        }

        return .completed()
    }

    static func applyOutcome(state: inout ProgressionState, graph: CurriculumGraph, conceptId: String, outcome: MasteryOutcome) {
        guard var concept = state.masteryByConcept[conceptId] else { return }

        concept.attemptCount += 1

        switch outcome {
        case .correct:
            concept.correctCount += 1
            concept.lastOutcome = .correct
            concept.needsRemediation = false
            concept.currentDifficulty = min(concept.currentDifficulty + AppConfig.masteryDifficultyUpStep, state.difficultyCeiling.maxLevel)
            concept.highestDifficultyPassed = max(concept.highestDifficultyPassed, concept.currentDifficulty)
        case .incorrect:
            concept.incorrectCount += 1
            concept.lastOutcome = .incorrect
            concept.currentDifficulty = max(1, concept.currentDifficulty - AppConfig.masteryDifficultyDownStep)
            if concept.incorrectCount >= AppConfig.masteryRemediationIncorrectThreshold {
                concept.needsRemediation = true
            }
        case .ambiguous:
            concept.lastOutcome = .ambiguous
            concept.currentDifficulty = max(1, concept.currentDifficulty - AppConfig.masteryDifficultyDownStep)
            concept.needsRemediation = true
        }

        if concept.correctCount >= AppConfig.masteryRequiredCorrectCount && concept.highestDifficultyPassed >= AppConfig.masteryRequiredDifficulty {
            concept.mastered = true
            concept.needsRemediation = false
        }

        state.masteryByConcept[conceptId] = concept
        state.currentConceptId = conceptId

        unlockLevelsIfNeeded(state: &state, graph: graph)

        let hasUnmastered = graph.orderedConceptIDs.contains { id in
            guard let mastery = state.masteryByConcept[id] else { return false }
            return !mastery.mastered && state.isConceptUnlocked(id, graph: graph)
        }
        state.topicCompleted = !hasUnmastered
    }

    private static func unlockLevelsIfNeeded(state: inout ProgressionState, graph: CurriculumGraph) {
        for level in graph.levels where !state.unlockedLevelIndices.contains(level.index) {
            let previousIndex = level.index - 1
            guard let previousLevel = graph.levels.first(where: { $0.index == previousIndex }) else { continue }
            let masteredCount = previousLevel.conceptIDs.reduce(0) { partial, conceptId in
                partial + ((state.masteryByConcept[conceptId]?.mastered ?? false) ? 1 : 0)
            }
            let ratio = Double(masteredCount) / Double(max(previousLevel.conceptIDs.count, 1))
            if ratio >= previousLevel.unlockThreshold {
                state.unlockedLevelIndices.append(level.index)
            }
        }
        state.unlockedLevelIndices = Array(Set(state.unlockedLevelIndices)).sorted()
    }
}

private extension ProgressionState {
    func isConceptUnlocked(_ conceptId: String, graph: CurriculumGraph) -> Bool {
        guard let concept = graph.concepts.first(where: { $0.id == conceptId }) else { return false }
        return unlockedLevelIndices.contains(concept.levelIndex)
    }
}
