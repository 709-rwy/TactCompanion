import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var showsOtherSeason: Bool {
        didSet { defaults.set(showsOtherSeason, forKey: Keys.showsOtherSeason) }
    }
    @Published var urgentDayCount: Int {
        didSet { defaults.set(urgentDayCount, forKey: Keys.urgentDayCount) }
    }
    @Published var referenceWeekday: Int {
        didSet { defaults.set(referenceWeekday, forKey: Keys.referenceWeekday) }
    }
    @Published var firstBoundaryWeek: Int {
        didSet { defaults.set(firstBoundaryWeek, forKey: Keys.firstBoundaryWeek) }
    }
    @Published var secondBoundaryWeek: Int {
        didSet { defaults.set(secondBoundaryWeek, forKey: Keys.secondBoundaryWeek) }
    }
    @Published var deadlineBoundaryHour: Int {
        didSet { defaults.set(deadlineBoundaryHour, forKey: Keys.deadlineBoundaryHour) }
    }
    @Published var deadlineBoundaryMinute: Int {
        didSet { defaults.set(deadlineBoundaryMinute, forKey: Keys.deadlineBoundaryMinute) }
    }
    @Published var deadlineNotificationsEnabled: Bool {
        didSet {
            defaults.set(
                deadlineNotificationsEnabled,
                forKey: Keys.deadlineNotificationsEnabled
            )
        }
    }
    @Published var notificationHour: Int {
        didSet { defaults.set(notificationHour, forKey: Keys.notificationHour) }
    }
    @Published var notificationMinute: Int {
        didSet { defaults.set(notificationMinute, forKey: Keys.notificationMinute) }
    }
    @Published var countsOverdueItems: Bool {
        didSet { defaults.set(countsOverdueItems, forKey: Keys.countsOverdueItems) }
    }

    private enum Keys {
        static let showsOtherSeason = "showsOtherSeason"
        static let urgentDayCount = "urgentDayCount"
        static let referenceWeekday = "referenceWeekday"
        static let firstBoundaryWeek = "firstBoundaryWeek"
        static let secondBoundaryWeek = "secondBoundaryWeek"
        static let deadlineBoundaryHour = "deadlineBoundaryHour"
        static let deadlineBoundaryMinute = "deadlineBoundaryMinute"
        static let deadlineNotificationsEnabled = "deadlineNotificationsEnabled"
        static let notificationHour = "notificationHour"
        static let notificationMinute = "notificationMinute"
        static let countsOverdueItems = "countsOverdueItems"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsOtherSeason = defaults.bool(forKey: Keys.showsOtherSeason)
        urgentDayCount = defaults.object(forKey: Keys.urgentDayCount) as? Int ?? 1
        referenceWeekday = defaults.object(forKey: Keys.referenceWeekday) as? Int ?? 7
        firstBoundaryWeek = defaults.object(forKey: Keys.firstBoundaryWeek) as? Int ?? 1
        secondBoundaryWeek = defaults.object(forKey: Keys.secondBoundaryWeek) as? Int ?? 2
        deadlineBoundaryHour =
            defaults.object(forKey: Keys.deadlineBoundaryHour) as? Int ?? 0
        deadlineBoundaryMinute =
            defaults.object(forKey: Keys.deadlineBoundaryMinute) as? Int ?? 0
        deadlineNotificationsEnabled =
            defaults.bool(forKey: Keys.deadlineNotificationsEnabled)
        notificationHour =
            defaults.object(forKey: Keys.notificationHour) as? Int ?? 9
        notificationMinute =
            defaults.object(forKey: Keys.notificationMinute) as? Int ?? 0
        countsOverdueItems = defaults.bool(forKey: Keys.countsOverdueItems)
    }

    var referenceWeekdayName: String {
        Self.weekdayNames[referenceWeekday] ?? "土曜日"
    }

    static let weekdayNames = [
        1: "日曜日",
        2: "月曜日",
        3: "火曜日",
        4: "水曜日",
        5: "木曜日",
        6: "金曜日",
        7: "土曜日"
    ]
}
