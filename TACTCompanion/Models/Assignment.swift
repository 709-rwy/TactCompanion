import Foundation

struct Assignment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let courseID: String
    let title: String
    let instructions: String?
    let dueDate: Date?
    let isSubmitted: Bool
    let tactURL: URL

    var isOverdue: Bool {
        guard let dueDate else { return false }
        return !isSubmitted && dueDate < .now
    }
}
