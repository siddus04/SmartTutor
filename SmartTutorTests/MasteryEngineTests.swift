import XCTest
@testable import SmartTutor

final class MasteryEngineTests: XCTestCase {
    func testBootstrapIncludesAllConcepts() {
        let state = MasteryEngine.bootstrapProgression(graph: .trianglesGrade6, ceiling: SessionStorage.grade6DifficultyCeiling)
        XCTAssertEqual(state.masteryByConcept.count, CurriculumGraph.trianglesGrade6.concepts.count)
        XCTAssertEqual(state.unlockedLevelIndices, [1])
        XCTAssertFalse(state.topicCompleted)
    }

    func testCorrectProgressionMastersConceptAndAdvances() {
        var state = MasteryEngine.bootstrapProgression(graph: .trianglesGrade6, ceiling: SessionStorage.grade6DifficultyCeiling)
        let first = CurriculumGraph.trianglesGrade6.levels[0].conceptIDs[0]

        for _ in 0..<3 {
            MasteryEngine.applyOutcome(state: &state, graph: .trianglesGrade6, conceptId: first, outcome: .correct)
        }

        XCTAssertEqual(state.masteryByConcept[first]?.mastered, true)
        let step = MasteryEngine.nextLearningStep(state: state, graph: .trianglesGrade6)
        XCTAssertNotEqual(step.conceptId, first)
    }

    func testIncorrectTriggersRemediation() {
        var state = MasteryEngine.bootstrapProgression(graph: .trianglesGrade6, ceiling: SessionStorage.grade6DifficultyCeiling)
        let first = CurriculumGraph.trianglesGrade6.levels[0].conceptIDs[0]

        MasteryEngine.applyOutcome(state: &state, graph: .trianglesGrade6, conceptId: first, outcome: .incorrect)

        let step = MasteryEngine.nextLearningStep(state: state, graph: .trianglesGrade6)
        XCTAssertEqual(step.conceptId, first)
        XCTAssertEqual(step.intent, .remediate)
    }
}
