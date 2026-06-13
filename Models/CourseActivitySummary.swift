import Foundation

struct CourseActivitySummary: Identifiable, Hashable, Sendable {
    let course: Course
    let pendingAssignmentCount: Int
    let pendingQuizCount: Int
    let announcementCount: Int

    var id: String {
        course.id
    }
}
