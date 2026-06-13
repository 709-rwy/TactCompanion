import Foundation

enum HiddenContentStore {
    static let didChangeNotification = Notification.Name(
        "HiddenContentStoreDidChange"
    )

    private static let deadlineKey = "hiddenDeadlineItemIDs"
    private static let announcementKey = "hiddenAnnouncementIDs"

    static var deadlineIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: deadlineKey) ?? [])
    }

    static var announcementIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: announcementKey) ?? [])
    }

    static func saveDeadlineIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: deadlineKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func saveAnnouncementIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: announcementKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: deadlineKey)
        UserDefaults.standard.removeObject(forKey: announcementKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func assignmentID(_ assignment: Assignment) -> String {
        "assignment-\(assignment.id)"
    }

    static func quizID(_ quiz: Quiz) -> String {
        "quiz-\(quiz.id)"
    }

    static func announcementID(_ announcement: Announcement) -> String {
        "\(announcement.courseID)-\(announcement.id)"
    }
}
