import Foundation

struct Announcement: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let courseID: String
    let title: String
    let body: String
    let publishedAt: Date
    let tactURL: URL

    var displayBody: String {
        body
            .replacingOccurrences(
                of: #"[ \t]+\n"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\n{2,}"#,
                with: "\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
