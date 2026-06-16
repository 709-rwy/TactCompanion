import Combine
import Foundation

@MainActor
final class TimetableViewModel: ObservableObject {
    @Published private(set) var courseSummaries: [CourseActivitySummary] = []
    @Published private(set) var isLoading = false
    @Published var selectedTerm: Course.Term {
        didSet {
            UserDefaults.standard.set(
                selectedTerm.rawValue,
                forKey: Self.selectedTermKey
            )
            WidgetSnapshotStore.updateCourses(
                courseSummaries.map(\.course),
                selectedTerm: selectedTerm
            )
        }
    }
    @Published var errorMessage: String?

    private let repository: any TactRepositoryProtocol
    private var cachedCounts: [String: CachedCounts]

    init(repository: any TactRepositoryProtocol) {
        self.repository = repository
        self.selectedTerm =
            UserDefaults.standard.string(forKey: Self.selectedTermKey)
                .flatMap(Course.Term.init(rawValue:)) ??
            Self.defaultTerm()
        self.cachedCounts = Self.loadCachedCounts()
    }

    var weekdays: [Course.Weekday] {
        Array(Course.Weekday.allCases.prefix(5))
    }

    var displayedSummaries: [CourseActivitySummary] {
        courseSummaries.filter {
            $0.course.academicYear == currentAcademicYear &&
            $0.course.isOffered(in: selectedTerm)
        }
    }

    var periods: ClosedRange<Int> {
        let maximumPeriod = displayedSummaries
            .flatMap(\.course.meetings)
            .map(\.period)
            .max() ?? 5
        return 1...max(5, maximumPeriod)
    }

    var unscheduledCourses: [CourseActivitySummary] {
        displayedSummaries.filter {
            $0.course.meetings.isEmpty ||
            $0.course.meetings.contains { $0.weekday.rawValue > 5 }
        }
    }

    var currentAcademicYear: Int {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: .now)
        let month = calendar.component(.month, from: .now)
        return month >= 4 ? year : year - 1
    }

    func summary(
        weekday: Course.Weekday,
        period: Int
    ) -> CourseActivitySummary? {
        displayedSummaries.first {
            $0.course.meetings.contains {
                $0.weekday == weekday && $0.period == period
            }
        }
    }

    func load(countsOverdueItems: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let courses = try await repository.fetchCourses()
            courseSummaries = courses
                .map {
                    let cached = cachedCounts[$0.id]
                    return CourseActivitySummary(
                        course: $0,
                        pendingAssignmentCount: cached?.assignments ?? 0,
                        pendingQuizCount: cached?.quizzes ?? 0,
                        announcementCount: cached?.announcements ?? 0
                    )
                }
                .sorted(by: Self.summaryOrder)
            WidgetSnapshotStore.updateCourses(
                courses,
                selectedTerm: selectedTerm
            )

            let preferredCourses = courses.filter {
                $0.isOffered(in: selectedTerm)
            }
            let remainingCourses = courses.filter {
                !$0.isOffered(in: selectedTerm)
            }
            await loadActivities(
                for: preferredCourses,
                countsOverdueItems: countsOverdueItems
            )
            await loadActivities(
                for: remainingCourses,
                countsOverdueItems: countsOverdueItems
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(countsOverdueItems: Bool) async {
        await repository.invalidateCaches()
        await load(countsOverdueItems: countsOverdueItems)
    }

    func recalculateCounts(countsOverdueItems: Bool) async {
        let courses = courseSummaries.map(\.course)
        await loadActivities(
            for: courses,
            countsOverdueItems: countsOverdueItems
        )
    }

    static var currentSeasonTerms: [Course.Term] {
        let month = Calendar.current.component(.month, from: .now)
        return (4...9).contains(month)
            ? [.spring1, .spring2]
            : [.autumn1, .autumn2]
    }

    private static let selectedTermKey = "selectedTimetableTerm"
    private static let cachedCountsKey = "cachedTimetableActivityCounts"

    private struct CachedCounts: Codable {
        var assignments: Int
        var quizzes: Int
        var announcements: Int
    }

    private enum ActivityKind: Sendable {
        case assignments
        case quizzes
        case announcements
    }

    private struct ActivityUpdate: Sendable {
        let courseID: String
        let kind: ActivityKind
        let count: Int
    }

    private func loadActivities(
        for courses: [Course],
        countsOverdueItems: Bool
    ) async {
        let hiddenDeadlines = HiddenContentStore.deadlineIDs
        let hiddenAnnouncements = HiddenContentStore.announcementIDs
        await withTaskGroup(of: ActivityUpdate.self) { group in
            for course in courses {
                group.addTask { [repository] in
                    let values = try? await repository.fetchAssignments(
                        courseID: course.id
                    )
                    return ActivityUpdate(
                        courseID: course.id,
                        kind: .assignments,
                        count: values?.filter {
                            !$0.isSubmitted &&
                            (countsOverdueItems || !$0.isOverdue) &&
                            !hiddenDeadlines.contains(
                                HiddenContentStore.assignmentID($0)
                            )
                        }.count ?? 0
                    )
                }
                group.addTask { [repository] in
                    let values = try? await repository.fetchQuizzes(
                        courseID: course.id
                    )
                    return ActivityUpdate(
                        courseID: course.id,
                        kind: .quizzes,
                        count: values?.filter {
                            !$0.isSubmitted &&
                            (countsOverdueItems || !$0.isOverdue) &&
                            !hiddenDeadlines.contains(
                                HiddenContentStore.quizID($0)
                            )
                        }.count ?? 0
                    )
                }
                group.addTask { [repository] in
                    let values = try? await repository.fetchAnnouncements(
                        courseID: course.id
                    )
                    return ActivityUpdate(
                        courseID: course.id,
                        kind: .announcements,
                        count: values?.filter {
                            !hiddenAnnouncements.contains(
                                HiddenContentStore.announcementID($0)
                            )
                        }.count ?? 0
                    )
                }
            }

            for await update in group {
                apply(update)
            }
        }
        saveCachedCounts()
    }

    private func apply(_ update: ActivityUpdate) {
        guard let index = courseSummaries.firstIndex(where: {
            $0.course.id == update.courseID
        }) else {
            return
        }
        let current = courseSummaries[index]
        var counts = cachedCounts[update.courseID] ?? CachedCounts(
            assignments: current.pendingAssignmentCount,
            quizzes: current.pendingQuizCount,
            announcements: current.announcementCount
        )
        switch update.kind {
        case .assignments:
            counts.assignments = update.count
        case .quizzes:
            counts.quizzes = update.count
        case .announcements:
            counts.announcements = update.count
        }
        cachedCounts[update.courseID] = counts
        courseSummaries[index] = CourseActivitySummary(
            course: current.course,
            pendingAssignmentCount: counts.assignments,
            pendingQuizCount: counts.quizzes,
            announcementCount: counts.announcements
        )
    }

    private static func loadCachedCounts() -> [String: CachedCounts] {
        guard
            let data = UserDefaults.standard.data(forKey: cachedCountsKey),
            let values = try? JSONDecoder().decode(
                [String: CachedCounts].self,
                from: data
            )
        else {
            return [:]
        }
        return values
    }

    private func saveCachedCounts() {
        guard let data = try? JSONEncoder().encode(cachedCounts) else { return }
        UserDefaults.standard.set(data, forKey: Self.cachedCountsKey)
    }

    private static func defaultTerm() -> Course.Term {
        switch Calendar.current.component(.month, from: .now) {
        case 4...6:
            return .spring1
        case 7...9:
            return .spring2
        case 10...12:
            return .autumn1
        default:
            return .autumn2
        }
    }

    private static func summaryOrder(
        _ lhs: CourseActivitySummary,
        _ rhs: CourseActivitySummary
    ) -> Bool {
        (lhs.course.weekday?.rawValue ?? Int.max,
         lhs.course.period ?? Int.max,
         lhs.course.title)
        <
        (rhs.course.weekday?.rawValue ?? Int.max,
         rhs.course.period ?? Int.max,
         rhs.course.title)
    }
}
