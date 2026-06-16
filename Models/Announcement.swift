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

    var bodyLinks: [URL] {
        guard !body.isEmpty else { return [] }

        var links: [URL] = []
        var seen = Set<URL>()

        func append(_ rawValue: String) {
            let decoded = Self.decodeHTMLEntities(rawValue)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                let url = Self.safeLinkURL(from: decoded),
                seen.insert(url).inserted
            else {
                return
            }
            links.append(url)
        }

        if let hrefExpression = try? NSRegularExpression(
            pattern: #"<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(body.startIndex..., in: body)
            for match in hrefExpression.matches(in: body, range: range) {
                guard let captureRange = Range(match.range(at: 1), in: body) else {
                    continue
                }
                append(String(body[captureRange]))
            }
        }

        let decodedText = Self.decodeHTMLEntities(body)
        if let urlExpression = try? NSRegularExpression(
            pattern: #"https?://[^\s<>"']+"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(decodedText.startIndex..., in: decodedText)
            for match in urlExpression.matches(in: decodedText, range: range) {
                guard let urlRange = Range(match.range, in: decodedText) else {
                    continue
                }
                append(
                    String(decodedText[urlRange]).trimmingCharacters(
                        in: CharacterSet(charactersIn: ".,;:!?)]}、。）」』")
                    )
                )
            }
        }

        return links
    }

    private static func safeLinkURL(from value: String) -> URL? {
        let baseURL = URL(string: "https://tact.ac.thers.ac.jp")!
        guard
            let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        var decoded = value
        let namedEntities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&lt;": "<",
            "&gt;": ">"
        ]
        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(
                of: entity,
                with: replacement,
                options: .caseInsensitive
            )
        }

        guard let expression = try? NSRegularExpression(
            pattern: #"&#(?:x([0-9a-fA-F]+)|([0-9]+));"#
        ) else {
            return decoded
        }

        let matches = expression.matches(
            in: decoded,
            range: NSRange(decoded.startIndex..., in: decoded)
        )
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: decoded) else {
                continue
            }
            let hexRange = Range(match.range(at: 1), in: decoded)
            let decimalRange = Range(match.range(at: 2), in: decoded)
            let scalarValue: UInt32?
            if let hexRange {
                scalarValue = UInt32(decoded[hexRange], radix: 16)
            } else if let decimalRange {
                scalarValue = UInt32(decoded[decimalRange], radix: 10)
            } else {
                scalarValue = nil
            }
            guard
                let scalarValue,
                let scalar = UnicodeScalar(scalarValue)
            else {
                continue
            }
            decoded.replaceSubrange(fullRange, with: String(scalar))
        }
        return decoded
    }
}
