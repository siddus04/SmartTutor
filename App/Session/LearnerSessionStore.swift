import Foundation
import Combine

@MainActor
final class LearnerSessionStore: ObservableObject {
    @Published private(set) var session: LearnerSession?

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isOnboardingComplete: Bool {
        session != nil
    }

    func loadSession() {
        guard let data = defaults.data(forKey: SessionStorage.sessionKey) else {
            session = nil
            return
        }

        do {
            var decoded = try decoder.decode(LearnerSession.self, from: data)
            guard isAllowedScope(decoded) else {
                resetSession()
                return
            }

            if decoded.progression.masteryByConcept.isEmpty {
                decoded.progression = MasteryEngine.bootstrapProgression(
                    graph: .trianglesGrade6,
                    ceiling: SessionStorage.grade6DifficultyCeiling
                )
            }

            decoded.sessionMeta.lastOpenedAtISO8601 = SessionStorage.timestampString(for: Date())
            session = decoded
            persistSession(decoded)
        } catch {
            resetSession()
        }
    }

    func initializeSession(grade: GradeLevel, topic: TopicKey) {
        let now = Date()
        let nowString = SessionStorage.timestampString(for: now)

        let created = LearnerSession(
            learner: LearnerProfile(grade: grade),
            curriculum: CurriculumSelection(subject: .geometry, topic: topic),
            progression: MasteryEngine.bootstrapProgression(
                graph: .trianglesGrade6,
                ceiling: SessionStorage.grade6DifficultyCeiling
            ),
            sessionMeta: SessionMeta(
                schemaVersion: SessionStorage.schemaVersion,
                createdAtISO8601: nowString,
                lastOpenedAtISO8601: nowString
            )
        )

        session = created
        persistSession(created)
    }


    func updateProgression(_ update: (inout ProgressionState) -> Void) {
        guard var existing = session else { return }
        update(&existing.progression)
        existing.sessionMeta.lastOpenedAtISO8601 = SessionStorage.timestampString(for: Date())
        session = existing
        persistSession(existing)
    }
    func resetSession() {
        defaults.removeObject(forKey: SessionStorage.sessionKey)
        session = nil
    }

    private func persistSession(_ value: LearnerSession) {
        guard let data = try? encoder.encode(value) else {
            return
        }

        defaults.set(data, forKey: SessionStorage.sessionKey)
    }

    private func isAllowedScope(_ value: LearnerSession) -> Bool {
        value.learner.grade == .grade6 &&
        value.curriculum.subject == .geometry &&
        value.curriculum.topic == .geometryTriangles &&
        value.sessionMeta.schemaVersion == SessionStorage.schemaVersion
    }
}
