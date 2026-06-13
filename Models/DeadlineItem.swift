import Foundation

struct DeadlineItem: Identifiable, Hashable, Sendable {
    enum Urgency: Hashable, Sendable {
        case overdue
        case dueSoon
        case beforeFirstBoundary
        case beforeSecondBoundary
        case later
        case noDeadline
    }

    enum Kind: String, Hashable, Sendable {
        case assignment = "課題"
        case quiz = "小テスト"

        var systemImage: String {
            switch self {
            case .assignment:
                return "doc.text"
            case .quiz:
                return "checklist"
            }
        }
    }

    let id: String
    let courseID: String
    let courseTitle: String
    let title: String
    let dueDate: Date?
    let kind: Kind
    let isOverdue: Bool
    let tactURL: URL
    let details: String?
    let availableFrom: Date?

    var displayDetails: String? {
        guard let details, !details.isEmpty else { return nil }
        let text = details
            .replacingOccurrences(
                of: #"<(?:script|style)\b[^>]*>[\s\S]*?</(?:script|style)>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"<\s*br\s*/?\s*>"#,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"</\s*(?:p|div|li|tr|h[1-6])\s*>"#,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"<\s*li\b[^>]*>"#,
                with: "・",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"<[^>]+>"#,
                with: "",
                options: .regularExpression
            )

        return Self.decodeHTMLEntities(text)
            .replacingOccurrences(
                of: #"\r\n?"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[ \t]+\n"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\n{3,}"#,
                with: "\n\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var detailLinks: [URL] {
        guard kind == .assignment, let details, !details.isEmpty else {
            return []
        }

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
            let range = NSRange(details.startIndex..., in: details)
            for match in hrefExpression.matches(in: details, range: range) {
                guard
                    let captureRange = Range(match.range(at: 1), in: details)
                else {
                    continue
                }
                append(String(details[captureRange]))
            }
        }

        let decodedText = Self.decodeHTMLEntities(details)
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
            guard
                let fullRange = Range(match.range(at: 0), in: decoded)
            else {
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

    func remainingTimeLabel(now: Date = .now) -> String? {
        guard let dueDate else { return nil }
        let remaining = dueDate.timeIntervalSince(now)
        guard remaining > 0 else { return "期限切れ" }

        let hour: TimeInterval = 60 * 60
        let day: TimeInterval = 24 * hour
        if remaining < day {
            return "\(max(Int(ceil(remaining / hour)), 1))時間以内"
        }

        let remainingDays = max(Int(ceil(remaining / day)), 1)
        if remainingDays < 14 {
            return "\(remainingDays)日以内"
        }
        return "\(Int(ceil(Double(remainingDays) / 7.0)))週間以内"
    }

    func urgency(
        urgentDayCount: Int,
        referenceWeekday: Int,
        firstBoundaryWeek: Int,
        secondBoundaryWeek: Int,
        boundaryHour: Int,
        boundaryMinute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Urgency {
        guard let dueDate else { return .noDeadline }
        if dueDate < now { return .overdue }

        let startOfToday = calendar.startOfDay(for: now)
        let boundaryComponents = DateComponents(
            hour: min(max(boundaryHour, 0), 23),
            minute: min(max(boundaryMinute, 0), 59)
        )
        guard
            let urgentLimitDay = calendar.date(
                byAdding: .day,
                value: max(urgentDayCount, 0) + 1,
                to: startOfToday
            ),
            let urgentLimit = calendar.date(
                bySettingHour: boundaryComponents.hour ?? 0,
                minute: boundaryComponents.minute ?? 0,
                second: 0,
                of: urgentLimitDay
            ),
            let nextReferenceDay = calendar.nextDate(
                after: startOfToday,
                matching: DateComponents(
                    hour: boundaryComponents.hour,
                    minute: boundaryComponents.minute,
                    weekday: referenceWeekday
                ),
                matchingPolicy: .nextTime
            ),
            let firstBoundary = calendar.date(
                byAdding: .day,
                value: max(firstBoundaryWeek - 1, 0) * 7,
                to: nextReferenceDay
            ),
            let secondBoundary = calendar.date(
                byAdding: .day,
                value: max(secondBoundaryWeek - 1, 0) * 7,
                to: nextReferenceDay
            )
        else {
            return .later
        }
        if dueDate < urgentLimit {
            return .dueSoon
        }
        if dueDate < firstBoundary {
            return .beforeFirstBoundary
        }
        if dueDate < secondBoundary {
            return .beforeSecondBoundary
        }
        return .later
    }
}
