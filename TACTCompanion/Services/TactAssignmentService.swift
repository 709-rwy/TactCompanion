import Foundation

struct TactAssignmentService: Sendable {
    private let session: TactSessionService

    init(session: TactSessionService) {
        self.session = session
    }

    func fetchAssignments(siteID: String) async throws -> [Assignment] {
        async let portalData = session.get(
            path: "/portal/site/\(siteID)",
            expectedFormat: .html,
            useCache: true
        )
        let encodedSiteID = siteID.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? siteID
        let data = try await session.get(
            path: "/direct/assignment/site/\(encodedSiteID).json"
        )
        let response = try JSONDecoder().decode(AssignmentResponse.self, from: data)
        let portalDataValue = try? await portalData
        let portalHTML = portalDataValue.flatMap {
            String(data: $0, encoding: .utf8)
        }
        let toolURL = portalHTML.flatMap(TactHTMLParser.assignmentToolURL)

        var assignments: [Assignment] = []
        for assignment in response.assignments {
            let detailURL: URL?
            if let toolURL {
                detailURL = makeAssignmentURL(
                    toolURL: toolURL,
                    siteID: siteID,
                    assignmentID: assignment.id
                )
            } else {
                detailURL = nil
            }

            let isSubmitted = assignment.safeSubmissions.contains { submission in
                (submission.userSubmission ?? false) &&
                (submission.submitted ?? false) &&
                !(submission.draft ?? false)
            }

            assignments.append(
                Assignment(
                id: assignment.id,
                courseID: assignment.context,
                title: assignment.title,
                instructions: assignment.instructions,
                dueDate: assignment.dueTime?.date,
                isSubmitted: isSubmitted,
                tactURL: detailURL ??
                    URL(string: assignment.entityURL) ??
                    URL(string: "https://tact.ac.thers.ac.jp/portal/site/\(assignment.context)")!
                )
            )
        }
        return assignments
    }

    private func makeAssignmentURL(
        toolURL: URL,
        siteID: String,
        assignmentID: String
    ) -> URL? {
        guard var components = URLComponents(url: toolURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = components.path.replacingOccurrences(
            of: "/tool-reset/",
            with: "/tool/"
        )
        components.queryItems = [
            URLQueryItem(
                name: "assignmentReference",
                value: "/assignment/a/\(siteID)/\(assignmentID)"
            ),
            URLQueryItem(name: "sakai_action", value: "doView_submission")
        ]
        return components.url
    }
}

private struct AssignmentResponse: Decodable {
    let assignments: [AssignmentDTO]

    enum CodingKeys: String, CodingKey {
        case assignments = "assignment_collection"
    }
}

private struct AssignmentDTO: Decodable {
    let id: String
    let context: String
    let title: String
    let instructions: String?
    let dueTime: TactInstant?
    let submissions: [SubmissionDTO]?
    let entityURL: String

    var safeSubmissions: [SubmissionDTO] {
        submissions ?? []
    }
}

private struct SubmissionDTO: Decodable {
    let submitted: Bool?
    let userSubmission: Bool?
    let draft: Bool?
}

private struct TactInstant: Decodable {
    let epochSecond: TimeInterval

    var date: Date {
        Date(timeIntervalSince1970: epochSecond)
    }
}
