import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    var text: String
    let isAssistant: Bool
}
