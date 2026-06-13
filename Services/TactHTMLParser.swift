import Foundation

enum TactHTMLParser {
    struct AnnouncementLink: Sendable {
        let id: String
        let title: String
        let publishedAt: Date
        let url: URL
    }

    static func courses(from html: String) -> [Course] {
        let tags = matches(
            pattern: #"<(?:a|button)\b[^>]*data-site-id="n_[^"]+"[^>]*title="[^"]+"[^>]*>"#,
            in: html,
            options: [.caseInsensitive]
        )

        var seenIDs = Set<String>()
        return tags.compactMap { tag in
            guard
                let id = attribute("data-site-id", in: tag),
                id.hasPrefix("n_"),
                !seenIDs.contains(id),
                let rawTitle = attribute("title", in: tag)
            else {
                return nil
            }
            seenIDs.insert(id)

            let decodedTitle = decodeHTMLEntities(rawTitle)
            let marker = " をお気に入りサイトに追加または削除"
            let accessMarker = "ツールにアクセスするためには "
            let accessSuffix = " が追加されたメニューを開きます"
            let displayTitle = decodedTitle
                .replacingOccurrences(of: marker, with: "")
                .replacingOccurrences(of: accessMarker, with: "")
                .replacingOccurrences(of: accessSuffix, with: "")
            let meetings = scheduleMeetings(from: displayTitle)
            let academicYear = firstCapture(
                pattern: #"\((\d{4})年度"#,
                in: displayTitle
            ).flatMap(Int.init)
            let terms = courseTerms(from: displayTitle)
            let courseTitle = displayTitle.replacingOccurrences(
                of: #"\(\d{4}年度[^()]*/[^()]*\)$"#,
                with: "",
                options: .regularExpression
            )

            return Course(
                id: id,
                title: courseTitle,
                instructorName: nil,
                room: nil,
                meetings: meetings,
                academicYear: academicYear,
                terms: terms,
                tactURL: URL(
                    string: "https://tact.ac.thers.ac.jp/portal/site/\(id)"
                )!
            )
        }
    }

    static func announcementToolURL(from html: String) -> URL? {
        toolURL(
            from: html,
            iconClass: "icon-sakai--sakai-announcements"
        )
    }

    static func assignmentToolURL(from html: String) -> URL? {
        toolURL(
            from: html,
            iconClass: "icon-sakai--sakai-assignment-grades"
        )
    }

    static func quizToolURL(from html: String) -> URL? {
        toolURL(
            from: html,
            iconClass: "icon-sakai--sakai-samigo"
        )
    }

    static func resourcesToolURL(from html: String) -> URL? {
        toolURL(
            from: html,
            iconClass: "icon-sakai--sakai-resources"
        )
    }

    static func courseMaterials(from html: String) -> [CourseMaterial] {
        let anchors = matches(
            pattern: #"<a\b[^>]*href="[^"]+"[^>]*>[\s\S]*?</a>"#,
            in: html,
            options: [.caseInsensitive]
        )
        var seenURLs = Set<URL>()

        return anchors.compactMap { anchor in
            guard
                let rawHref = attribute("href", in: anchor),
                let url = absoluteTACTURL(from: decodeHTMLEntities(rawHref)),
                url.path.lowercased().contains("/access/content/"),
                !url.path.hasSuffix("/"),
                !seenURLs.contains(url)
            else {
                return nil
            }
            seenURLs.insert(url)

            let rawTitle = anchor.replacingOccurrences(
                of: #"<[^>]+>"#,
                with: " ",
                options: .regularExpression
            )
            let title = decodeHTMLEntities(rawTitle)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            let fallbackTitle = url.lastPathComponent
                .removingPercentEncoding ?? url.lastPathComponent

            return CourseMaterial(
                id: url.absoluteString,
                title: title.isEmpty ? fallbackTitle : title,
                url: url,
                kind: materialKind(for: url)
            )
        }
    }

    static func resourceFolders(
        from html: String,
        pageURL: URL? = nil
    ) -> [CourseMaterial] {
        let folderAnchors = matches(
            pattern: #"<a\b[^>]*class="[^"]*fa-folder[^"]*"[^>]*>[\s\S]*?</a>"#,
            in: html,
            options: [.caseInsensitive]
        )
        var seenURLs = Set<URL>()

        var folders = folderAnchors.compactMap { anchor -> CourseMaterial? in
            guard
                let collectionID =
                    attribute("name", in: anchor) ??
                    firstCapture(
                        pattern: #"collectionId[^=]*\.value='([^']+)'"#,
                        in: anchor,
                        options: [.caseInsensitive]
                    ),
                let pageURL,
                let url = resourceFolderURL(
                    pageURL: pageURL,
                    collectionID: decodeHTMLEntities(collectionID)
                ),
                !seenURLs.contains(url)
            else {
                return nil
            }
            seenURLs.insert(url)

            let title = collectionID
                .split(separator: "/")
                .last
                .map(String.init)?
                .removingPercentEncoding ?? anchorTitle(
                    anchor,
                    fallbackURL: url
                )
            return CourseMaterial(
                id: "folder-\(url.absoluteString)",
                title: title,
                url: url,
                kind: .folder
            )
        }

        if let pageURL {
            let rows = matches(
                pattern: #"<tr\b[^>]*>[\s\S]*?collectionId[\s\S]*?</tr>"#,
                in: html,
                options: [.caseInsensitive]
            )
            for row in rows {
                guard
                    let collectionID =
                        firstCapture(
                            pattern: #"collectionId(?:\.value)?\s*=\s*['"]([^'"]+)['"]"#,
                            in: row,
                            options: [.caseInsensitive]
                        ) ??
                        firstCapture(
                            pattern: #"name="collectionId"[^>]*value="([^"]+)""#,
                            in: row,
                            options: [.caseInsensitive]
                        ),
                    let url = resourceFolderURL(
                        pageURL: pageURL,
                        collectionID: decodeHTMLEntities(collectionID)
                    ),
                    !seenURLs.contains(url)
                else {
                    continue
                }
                seenURLs.insert(url)

                let title = anchorTitle(row, fallbackURL: url)
                folders.append(
                    CourseMaterial(
                        id: "folder-\(url.absoluteString)",
                        title: title,
                        url: url,
                        kind: .folder
                    )
                )
            }
        }
        return folders
    }

    static func resourceFormFields(from html: String) -> [String: String] {
        let hiddenInputs = matches(
            pattern: #"<input\b[^>]*type="hidden"[^>]*>"#,
            in: html,
            options: [.caseInsensitive]
        )
        return hiddenInputs.reduce(into: [:]) { fields, input in
            guard let name = attribute("name", in: input) else { return }
            fields[name] = decodeHTMLEntities(
                attribute("value", in: input) ?? ""
            )
        }
    }

    private static func toolURL(
        from html: String,
        iconClass: String
    ) -> URL? {
        let anchors = matches(
            pattern: #"<a\b[^>]*href="[^"]+"[^>]*>[\s\S]*?</a>"#,
            in: html,
            options: [.caseInsensitive]
        )
        return anchors
            .filter { $0.contains(iconClass) }
            .compactMap { attribute("href", in: $0).flatMap(URL.init(string:)) }
            .first {
                $0.path.contains("/portal/site/") &&
                ($0.path.contains("/tool/") || $0.path.contains("/tool-reset/"))
            }
    }

    private static func absoluteTACTURL(from value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        guard let baseURL = URL(string: "https://tact.ac.thers.ac.jp") else {
            return nil
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func materialKind(for url: URL) -> CourseMaterial.Kind {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "html", "htm":
            return .html
        default:
            return .other
        }
    }

    private static func anchorTitle(
        _ anchor: String,
        fallbackURL: URL
    ) -> String {
        let rawTitle = anchor.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let title = decodeHTMLEntities(rawTitle)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let fallbackTitle = fallbackURL.lastPathComponent
            .removingPercentEncoding ?? fallbackURL.lastPathComponent
        return title.isEmpty ? fallbackTitle : title
    }

    private static func resourceFolderURL(
        pageURL: URL,
        collectionID: String
    ) -> URL? {
        guard var components = URLComponents(
            url: pageURL,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll {
            ["collectionid", "sakai_action"].contains($0.name.lowercased())
        }
        queryItems.append(
            URLQueryItem(name: "collectionId", value: collectionID)
        )
        queryItems.append(
            URLQueryItem(name: "sakai_action", value: "doNavigate")
        )
        components.queryItems = queryItems
        return components.url
    }

    static func announcementLinks(from html: String) -> [AnnouncementLink] {
        let rows = matches(
            pattern: #"<tr\b[^>]*>[\s\S]*?itemReference=/announcement/msg/[\s\S]*?</tr>"#,
            in: html,
            options: [.caseInsensitive]
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy/MM/dd H:mm"

        return rows.compactMap { row in
            guard
                let href = attribute(
                    "href",
                    in: firstMatch(
                        pattern: #"<a\b[^>]*itemReference=/announcement/msg/[^>]*>"#,
                        in: row,
                        options: [.caseInsensitive]
                    ) ?? ""
                ),
                let url = URL(string: decodeHTMLEntities(href)),
                let reference = firstCapture(
                    pattern: #"itemReference=/announcement/msg/[^/]+/main/([^&"]+)"#,
                    in: href
                ),
                let titleAttribute = attribute(
                    "title",
                    in: firstMatch(
                        pattern: #"<a\b[^>]*itemReference=/announcement/msg/[^>]*>"#,
                        in: row,
                        options: [.caseInsensitive]
                    ) ?? ""
                ),
                let dateText = firstCapture(
                    pattern: #"<td\b[^>]*headers="date"[^>]*>\s*([^<]+)"#,
                    in: row,
                    options: [.caseInsensitive]
                ),
                let publishedAt = formatter.date(
                    from: decodeHTMLEntities(dateText)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            else {
                return nil
            }

            let title = decodeHTMLEntities(titleAttribute)
                .replacingOccurrences(of: "お知らせを表示 ", with: "")
            return AnnouncementLink(
                id: reference,
                title: title,
                publishedAt: publishedAt,
                url: url
            )
        }
    }

    static func announcementBody(from html: String) -> String {
        guard let body = firstCapture(
            pattern: #"<div\b[^>]*class="[^"]*message-body[^"]*"[^>]*>([\s\S]*?)</div>"#,
            in: html,
            options: [.caseInsensitive]
        ) else {
            return ""
        }

        return decodeHTMLEntities(
            body.replacingOccurrences(
                of: #"<[^>]+>"#,
                with: " ",
                options: .regularExpression
            )
        )
        .replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func submittedQuizTitles(from html: String) -> Set<String> {
        guard let tableBody = firstCapture(
            pattern: #"<tbody\b[^>]*id="[^"]*reviewTabl[^"]*"[^>]*>([\s\S]*?)</tbody>"#,
            in: html,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        return Set(
            matches(
                pattern: #"<tr\b[^>]*>([\s\S]*?)</tr>"#,
                in: tableBody,
                options: [.caseInsensitive]
            ).compactMap { row in
                guard let firstCell = firstCapture(
                    pattern: #"<td\b[^>]*>([\s\S]*?)</td>"#,
                    in: row,
                    options: [.caseInsensitive]
                ) else {
                    return nil
                }
                let title = decodeHTMLEntities(
                    firstCell.replacingOccurrences(
                        of: #"<[^>]+>"#,
                        with: "",
                        options: .regularExpression
                    )
                )
                .replacingOccurrences(
                    of: #"\s+"#,
                    with: " ",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? nil : title
            }
        )
    }

    private static func scheduleMeetings(from title: String) -> [Course.Meeting] {
        matches(
            pattern: #"[月火水木金土日][0-9０-９]{1,2}限"#,
            in: title
        ).compactMap { value in
            let periodText = normalizeFullWidthDigits(
                String(value.dropFirst().dropLast())
            )
            guard
                let weekday = Course.Weekday(
                    shortName: String(value.prefix(1))
                ),
                let period = Int(periodText)
            else {
                return nil
            }
            return Course.Meeting(weekday: weekday, period: period)
        }
    }

    private static func courseTerms(from title: String) -> Set<Course.Term> {
        let normalized = normalizeFullWidthDigits(title)
        var terms = Set<Course.Term>()

        if normalized.contains("春1期") {
            terms.insert(.spring1)
        }
        if normalized.contains("春2期") {
            terms.insert(.spring2)
        }
        if normalized.contains("秋1期") {
            terms.insert(.autumn1)
        }
        if normalized.contains("秋2期") {
            terms.insert(.autumn2)
        }
        if normalized.range(of: #"春(?![12]期)"#, options: .regularExpression) != nil {
            terms.formUnion([.spring1, .spring2])
        }
        if normalized.range(of: #"秋(?![12]期)"#, options: .regularExpression) != nil {
            terms.formUnion([.autumn1, .autumn2])
        }
        if normalized.contains("通年") || normalized.contains("未確定") {
            terms.formUnion(Course.Term.allCases)
        }
        return terms
    }

    private static func normalizeFullWidthDigits(_ value: String) -> String {
        let fullWidthDigits = Array("０１２３４５６７８９")
        let asciiDigits = Array("0123456789")
        return String(value.map { character in
            guard let index = fullWidthDigits.firstIndex(of: character) else {
                return character
            }
            return asciiDigits[index]
        })
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        firstCapture(
            pattern: #"\#(name)\s*=\s*"([^"]*)""#,
            in: tag,
            options: [.caseInsensitive]
        )
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        var decoded = value
        let replacements = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " "
        ]
        for (entity, character) in replacements {
            decoded = decoded.replacingOccurrences(of: entity, with: character)
        }
        return decoded
    }

    private static func matches(
        pattern: String,
        in value: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: options
        ) else {
            return []
        }
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }

    private static func firstMatch(
        pattern: String,
        in value: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        matches(pattern: pattern, in: value, options: options).first
    }

    private static func firstCapture(
        pattern: String,
        in value: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: options
            ),
            let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: value)
        else {
            return nil
        }
        return String(value[range])
    }
}
