import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct WidgetCourseSnapshot: Codable, Sendable {
    let id: String
    let title: String
    let weekday: Int?
    let period: Int?
    let terms: [String]
}

struct WidgetDeadlineSnapshot: Codable, Sendable {
    let id: String
    let title: String
    let courseTitle: String
    let dueDate: Date?
    let kind: String
    let urgency: String?
}

struct WidgetSnapshot: Codable, Sendable {
    var courses: [WidgetCourseSnapshot] = []
    var deadlines: [WidgetDeadlineSnapshot] = []
    var selectedTerm = Course.Term.spring1.rawValue
    var updatedAt = Date.now
}

enum WidgetSnapshotStore {
    static let appGroupID = "group.jp.ac.thers.TACTCompanion"
    private static let snapshotKey = "widgetSnapshot"

    static func updateCourses(
        _ courses: [Course],
        selectedTerm: Course.Term
    ) {
        var snapshot = load()
        snapshot.courses = courses.map {
            WidgetCourseSnapshot(
                id: $0.id,
                title: $0.title,
                weekday: $0.weekday?.rawValue,
                period: $0.period,
                terms: $0.terms.map(\.rawValue)
            )
        }
        snapshot.selectedTerm = selectedTerm.rawValue
        save(snapshot)
    }

    static func updateDeadlines(
        _ items: [DeadlineItem],
        urgentDayCount: Int,
        referenceWeekday: Int,
        firstBoundaryWeek: Int,
        secondBoundaryWeek: Int,
        boundaryHour: Int,
        boundaryMinute: Int
    ) {
        var snapshot = load()
        snapshot.deadlines = items.map {
            let urgency = $0.urgency(
                urgentDayCount: urgentDayCount,
                referenceWeekday: referenceWeekday,
                firstBoundaryWeek: firstBoundaryWeek,
                secondBoundaryWeek: secondBoundaryWeek,
                boundaryHour: boundaryHour,
                boundaryMinute: boundaryMinute
            )
            return WidgetDeadlineSnapshot(
                id: $0.id,
                title: $0.title,
                courseTitle: $0.courseTitle,
                dueDate: $0.dueDate,
                kind: $0.kind.rawValue,
                urgency: urgency.widgetValue
            )
        }
        save(snapshot)
    }

    static func clear() {
        UserDefaults(suiteName: appGroupID)?.removeObject(
            forKey: snapshotKey
        )
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private static func load() -> WidgetSnapshot {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(
                WidgetSnapshot.self,
                from: data
            )
        else {
            return WidgetSnapshot()
        }
        return snapshot
    }

    private static func save(_ snapshot: WidgetSnapshot) {
        var value = snapshot
        value.updatedAt = .now
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = try? JSONEncoder().encode(value)
        else {
            return
        }
        defaults.set(data, forKey: snapshotKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

private extension DeadlineItem.Urgency {
    var widgetValue: String {
        switch self {
        case .overdue: return "red"
        case .dueSoon: return "orange"
        case .beforeFirstBoundary: return "yellow"
        case .beforeSecondBoundary: return "green"
        case .later, .noDeadline: return "none"
        }
    }
}
