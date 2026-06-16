import Foundation

struct TactMaterialService: Sendable {
    struct Result: Codable, Sendable {
        let materials: [CourseMaterial]
        let resourcesURL: URL?
    }

    private let session: TactSessionService

    init(session: TactSessionService) {
        self.session = session
    }

    func fetchMaterials(siteID: String) async throws -> Result {
        let portalData = try await session.get(
            path: "/portal/site/\(siteID)",
            expectedFormat: .html,
            useCache: true
        )
        guard let portalHTML = String(data: portalData, encoding: .utf8) else {
            throw TactSessionService.SessionError.unexpectedResponse
        }
        guard let resourcesURL = TactHTMLParser.resourcesToolURL(from: portalHTML) else {
            return Result(materials: [], resourcesURL: nil)
        }

        let materials = await loadRootMaterials(from: resourcesURL)
        return Result(
            materials: materials,
            resourcesURL: resourcesURL
        )
    }

    private func loadRootMaterials(from url: URL) async -> [CourseMaterial] {
        guard
            let data = try? await session.get(
                url: url,
                expectedFormat: .html,
                useCache: true
            ),
            let html = String(data: data, encoding: .utf8)
        else {
            return []
        }

        var visitedCollections = Set<String>()
        let rootCollectionID =
            TactHTMLParser.resourceFormFields(from: html)["collectionId"]
        return await materials(
            from: html,
            toolURL: url,
            collectionID: rootCollectionID,
            depth: 0,
            visitedCollections: &visitedCollections
        )
    }

    private func materials(
        from html: String,
        toolURL: URL,
        collectionID: String?,
        depth: Int,
        visitedCollections: inout Set<String>
    ) async -> [CourseMaterial] {
        var values = TactHTMLParser.courseMaterials(from: html)
            .filter {
                guard let collectionID else { return true }
                return parentCollectionID(for: $0.url) == collectionID
            }
        guard depth < 6, visitedCollections.count < 50 else {
            return sorted(values)
        }

        let fields = TactHTMLParser.resourceFormFields(from: html)
        let folders = TactHTMLParser.resourceFolders(
            from: html,
            pageURL: toolURL
        ).filter {
            guard
                let collectionID,
                let folderCollectionID = self.collectionID(from: $0.url)
            else {
                return true
            }
            return parentCollectionID(of: folderCollectionID) == collectionID
        }

        for var folder in folders {
            guard
                let collectionID = self.collectionID(from: folder.url),
                visitedCollections.insert(collectionID).inserted
            else {
                continue
            }

            var folderFields = fields
            folderFields["collectionId"] = collectionID
            folderFields["sakai_action"] = "doExpand_collection"
            folderFields["navRoot"] = ""

            if
                let data = try? await session.postForm(
                    url: toolURL,
                    fields: folderFields
                ),
                let folderHTML = String(data: data, encoding: .utf8)
            {
                folder.children = await materials(
                    from: folderHTML,
                    toolURL: toolURL,
                    collectionID: collectionID,
                    depth: depth + 1,
                    visitedCollections: &visitedCollections
                )
            }

            if folder.children.isEmpty,
               let data = try? await session.get(
                   url: folder.url,
                   expectedFormat: .html,
                   useCache: false
               ),
               let folderHTML = String(data: data, encoding: .utf8) {
                folder.children = await materials(
                    from: folderHTML,
                    toolURL: toolURL,
                    collectionID: collectionID,
                    depth: depth + 1,
                    visitedCollections: &visitedCollections
                )
            }
            values.append(folder)
        }

        return sorted(values)
    }

    private func collectionID(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == "collectionid" }?
            .value
    }

    private func parentCollectionID(for fileURL: URL) -> String {
        let contentPrefix = "/access/content"
        let path = fileURL.path.hasPrefix(contentPrefix)
            ? String(fileURL.path.dropFirst(contentPrefix.count))
            : fileURL.path
        return parentCollectionID(of: path)
    }

    private func parentCollectionID(of collectionID: String) -> String {
        var components = collectionID.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return "/" }
        components.removeLast()
        return "/" + components.joined(separator: "/") + "/"
    }

    private func sorted(_ materials: [CourseMaterial]) -> [CourseMaterial] {
        materials.sorted {
            if $0.kind == .folder, $1.kind != .folder {
                return true
            }
            if $0.kind != .folder, $1.kind == .folder {
                return false
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}
