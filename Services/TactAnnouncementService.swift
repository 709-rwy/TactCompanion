import Foundation

struct TactAnnouncementService: Sendable {
    private let session: TactSessionService

    init(session: TactSessionService) {
        self.session = session
    }

    func fetchAnnouncements(siteID: String) async throws -> [Announcement] {
        let portalData = try await session.get(
            path: "/portal/site/\(siteID)",
            expectedFormat: .html,
            useCache: true
        )
        guard
            let portalHTML = String(data: portalData, encoding: .utf8),
            let toolURL = TactHTMLParser.announcementToolURL(from: portalHTML)
        else {
            return []
        }

        let listData = try await session.get(
            url: toolURL,
            expectedFormat: .html
        )
        guard let listHTML = String(data: listData, encoding: .utf8) else {
            throw TactSessionService.SessionError.unexpectedResponse
        }

        let links = TactHTMLParser.announcementLinks(from: listHTML)
        return links
            .map { link in
                Announcement(
                    id: link.id,
                    courseID: siteID,
                    title: link.title,
                    body: "",
                    publishedAt: link.publishedAt,
                    tactURL: link.url
                )
            }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    func fetchBody(url: URL) async throws -> String {
        let data = try await session.get(
            url: url,
            expectedFormat: .html,
            useCache: true
        )
        guard let html = String(data: data, encoding: .utf8) else {
            throw TactSessionService.SessionError.unexpectedResponse
        }
        return TactHTMLParser.announcementBody(from: html)
    }
}
