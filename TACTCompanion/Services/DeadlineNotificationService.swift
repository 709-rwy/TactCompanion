import Foundation
import UserNotifications

actor DeadlineNotificationService {
    struct Configuration: Hashable, Sendable {
        let isEnabled: Bool
        let urgentDayCount: Int
        let referenceWeekday: Int
        let firstBoundaryWeek: Int
        let secondBoundaryWeek: Int
        let boundaryHour: Int
        let boundaryMinute: Int
        let notificationHour: Int
        let notificationMinute: Int
    }

    private let repository: any TactRepositoryProtocol
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "deadline-due-soon-"

    init(repository: any TactRepositoryProtocol) {
        self.repository = repository
    }

    func update(configuration: Configuration) async {
        await removeScheduledNotifications()
        guard configuration.isEnabled else { return }

        let settings = await center.notificationSettings()
        guard
            settings.authorizationStatus == .authorized ||
            settings.authorizationStatus == .provisional
        else {
            return
        }

        guard let courses = try? await repository.fetchCourses() else { return }
        let items = await withTaskGroup(
            of: [DeadlineItem].self,
            returning: [DeadlineItem].self
        ) { group in
            for course in courses {
                group.addTask { [repository] in
                    async let assignments = try? repository.fetchAssignments(
                        courseID: course.id
                    )
                    async let quizzes = try? repository.fetchQuizzes(
                        courseID: course.id
                    )

                    let assignmentItems = await assignments ?? []
                    let quizItems = await quizzes ?? []
                    return assignmentItems
                        .filter { !$0.isSubmitted }
                        .map {
                            DeadlineItem(
                                id: "assignment-\($0.id)",
                                courseID: course.id,
                                courseTitle: course.title,
                                title: $0.title,
                                dueDate: $0.dueDate,
                                kind: .assignment,
                                isOverdue: $0.isOverdue,
                                tactURL: $0.tactURL,
                                details: $0.instructions,
                                availableFrom: nil
                            )
                        } +
                        quizItems
                        .filter { !$0.isSubmitted }
                        .map {
                            DeadlineItem(
                                id: "quiz-\($0.id)",
                                courseID: course.id,
                                courseTitle: course.title,
                                title: $0.title,
                                dueDate: $0.dueDate,
                                kind: .quiz,
                                isOverdue: $0.isOverdue,
                                tactURL: $0.tactURL,
                                details: nil,
                                availableFrom: $0.availableFrom
                            )
                        }
                }
            }

            var values: [DeadlineItem] = []
            for await courseItems in group {
                values.append(contentsOf: courseItems)
            }
            return values
        }

        for item in items {
            guard let fireDate = notificationDate(
                for: item,
                configuration: configuration
            ) else {
                continue
            }
            await schedule(item: item, at: fireDate)
        }
    }

    private func notificationDate(
        for item: DeadlineItem,
        configuration: Configuration,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard let dueDate = item.dueDate, dueDate > now else { return nil }
        var day = calendar.startOfDay(for: now)
        let lastDay = calendar.startOfDay(for: dueDate)

        while day <= lastDay {
            guard
                let candidate = calendar.date(
                    bySettingHour: configuration.notificationHour,
                    minute: configuration.notificationMinute,
                    second: 0,
                    of: day
                )
            else {
                return nil
            }

            if
                candidate > now,
                candidate < dueDate,
                item.urgency(
                    urgentDayCount: configuration.urgentDayCount,
                    referenceWeekday: configuration.referenceWeekday,
                    firstBoundaryWeek: configuration.firstBoundaryWeek,
                    secondBoundaryWeek: configuration.secondBoundaryWeek,
                    boundaryHour: configuration.boundaryHour,
                    boundaryMinute: configuration.boundaryMinute,
                    now: candidate,
                    calendar: calendar
                ) == .dueSoon
            {
                return candidate
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                return nil
            }
            day = nextDay
        }
        return nil
    }

    private func schedule(item: DeadlineItem, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "提出期限が近づいています"
        content.body = "\(item.courseTitle)「\(item.title)」"
        content.sound = .default
        content.userInfo = ["url": item.tactURL.absoluteString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let request = UNNotificationRequest(
            identifier: identifierPrefix + item.id,
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
        )
        try? await center.add(request)
    }

    private func removeScheduledNotifications() async {
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
