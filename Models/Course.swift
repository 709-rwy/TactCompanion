import Foundation

struct Course: Identifiable, Codable, Hashable, Sendable {
    enum Semester: String, CaseIterable, Hashable, Sendable {
        case spring = "春期"
        case autumn = "秋期"
    }

    enum Term: String, Codable, CaseIterable, Hashable, Sendable {
        case spring1 = "春1期"
        case spring2 = "春2期"
        case autumn1 = "秋1期"
        case autumn2 = "秋2期"

        var displayName: String {
            rawValue
        }
    }

    struct Meeting: Codable, Hashable, Sendable {
        let weekday: Weekday
        let period: Int
    }

    let id: String
    let title: String
    let instructorName: String?
    let room: String?
    let meetings: [Meeting]
    let academicYear: Int?
    let terms: Set<Term>
    let tactURL: URL

    var weekday: Weekday? {
        meetings.first?.weekday
    }

    var period: Int? {
        meetings.first?.period
    }

    func isOffered(in term: Term) -> Bool {
        terms.contains(term)
    }

    func isOffered(in semester: Semester) -> Bool {
        switch semester {
        case .spring:
            return !terms.isDisjoint(with: [.spring1, .spring2])
        case .autumn:
            return !terms.isDisjoint(with: [.autumn1, .autumn2])
        }
    }

    enum Weekday: Int, Codable, CaseIterable, Sendable {
        case monday = 1
        case tuesday
        case wednesday
        case thursday
        case friday
        case saturday
        case sunday

        var shortName: String {
            ["月", "火", "水", "木", "金", "土", "日"][rawValue - 1]
        }

        init?(shortName: String) {
            guard let index = ["月", "火", "水", "木", "金", "土", "日"]
                .firstIndex(of: shortName) else {
                return nil
            }
            self.init(rawValue: index + 1)
        }
    }
}
