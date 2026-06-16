import Foundation

struct TactQuizService: Sendable {
    private let session: TactSessionService

    init(session: TactSessionService) {
        self.session = session
    }

    func fetchQuizzes(siteID: String) async throws -> [Quiz] {
        async let portalData = session.get(
            path: "/portal/site/\(siteID)",
            expectedFormat: .html,
            useCache: true
        )
        let encodedSiteID = siteID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? siteID
        let data = try await session.get(
            path: "/direct/sam_pub/context/\(encodedSiteID).json"
        )
        let response = try JSONDecoder().decode(QuizResponse.self, from: data)
        let portalDataValue = try? await portalData
        let portalHTML = portalDataValue.flatMap {
            String(data: $0, encoding: .utf8)
        }
        let toolURL = portalHTML.flatMap(TactHTMLParser.quizToolURL)
        let submittedTitles: Set<String>
        if !response.quizzes.isEmpty, let toolURL {
            let toolData = try? await session.get(
                url: toolURL,
                expectedFormat: .html,
                useCache: false
            )
            let toolHTML = toolData.flatMap {
                String(data: $0, encoding: .utf8)
            }
            submittedTitles = toolHTML.map(
                TactHTMLParser.submittedQuizTitles
            ) ?? []
        } else {
            submittedTitles = []
        }

        return response.quizzes.map {
            Quiz(
                id: String($0.publishedAssessmentId),
                courseID: siteID,
                title: $0.title,
                availableFrom: Date(millisecondsSince1970: $0.startDate),
                dueDate: Date(millisecondsSince1970: $0.dueDate),
                isSubmitted: submittedTitles.contains(
                    normalizedTitle($0.title)
                ),
                tactURL: toolURL ??
                    URL(string: $0.entityURL) ??
                    URL(string: "https://tact.ac.thers.ac.jp/portal/site/\(siteID)")!
            )
        }
    }

    private func normalizedTitle(_ title: String) -> String {
        title
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct QuizResponse: Decodable {
    let quizzes: [QuizDTO]

    enum CodingKeys: String, CodingKey {
        case quizzes = "sam_pub_collection"
    }
}

private struct QuizDTO: Decodable {
    let publishedAssessmentId: Int
    let title: String
    let startDate: TimeInterval?
    let dueDate: TimeInterval?
    let entityURL: String
}

private extension Date {
    init?(millisecondsSince1970 value: TimeInterval?) {
        guard let value else { return nil }
        self.init(timeIntervalSince1970: value / 1_000)
    }
}
