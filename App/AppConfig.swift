import Foundation

enum AppConfig {
    static let baseURL: String = {
        if let value = ProcessInfo.processInfo.environment["BASE_URL"], !value.isEmpty {
            return value
        }
        return "http://localhost:8000"
    }()

    static let aiCheckBaseURL: String = "https://smart-tutor-chi.vercel.app/"
}

enum UIFlags {
    static let showBottomPrompt = false
}

enum DebugFlags {
    static let showSelectionDebug = true
    static let showLogOverlay = true
}

enum SessionStorage {
    static let sessionKey = "smarttutor.learnerSession.v1"
    static let schemaVersion = 1
    static let defaultConceptGraphID = "g6.geometry.triangles.v1"
    static let grade6DifficultyCeiling = 4

    static func timestampString(for date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
