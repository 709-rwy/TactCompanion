import Combine
import Foundation

@MainActor
final class CourseDetailViewModel: ObservableObject {
    @Published private(set) var assignments: [Assignment] = []
    @Published private(set) var quizzes: [Quiz] = []
    @Published private(set) var announcements: [Announcement] = []
    @Published private(set) var materials: [CourseMaterial] = []
    @Published private(set) var resourcesURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMaterials = false
    @Published private(set) var loadingAnnouncementIDs: Set<String> = []
    @Published var errorMessage: String?

    private let courseID: String
    private let repository: any TactRepositoryProtocol
    @Published private var hiddenDeadlineIDs: Set<String>
    @Published private var hiddenAnnouncementIDs: Set<String>
    private var hiddenContentObserver: NSObjectProtocol?

    init(courseID: String, repository: any TactRepositoryProtocol) {
        self.courseID = courseID
        self.repository = repository
        hiddenDeadlineIDs = HiddenContentStore.deadlineIDs
        hiddenAnnouncementIDs = HiddenContentStore.announcementIDs
        hiddenContentObserver = NotificationCenter.default.addObserver(
            forName: HiddenContentStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hiddenDeadlineIDs = HiddenContentStore.deadlineIDs
                self?.hiddenAnnouncementIDs = HiddenContentStore.announcementIDs
            }
        }
    }

    deinit {
        if let hiddenContentObserver {
            NotificationCenter.default.removeObserver(hiddenContentObserver)
        }
    }

    func visibleAssignments(countsOverdueItems: Bool) -> [Assignment] {
        eligibleAssignments(countsOverdueItems: countsOverdueItems).filter {
            !hiddenDeadlineIDs.contains(HiddenContentStore.assignmentID($0))
        }
    }

    func visibleQuizzes(countsOverdueItems: Bool) -> [Quiz] {
        eligibleQuizzes(countsOverdueItems: countsOverdueItems).filter {
            !hiddenDeadlineIDs.contains(HiddenContentStore.quizID($0))
        }
    }

    func hiddenAssignmentCount(countsOverdueItems: Bool) -> Int {
        eligibleAssignments(countsOverdueItems: countsOverdueItems).filter {
            hiddenDeadlineIDs.contains(HiddenContentStore.assignmentID($0))
        }.count
    }

    func hiddenQuizCount(countsOverdueItems: Bool) -> Int {
        eligibleQuizzes(countsOverdueItems: countsOverdueItems).filter {
            hiddenDeadlineIDs.contains(HiddenContentStore.quizID($0))
        }.count
    }

    var visibleAnnouncements: [Announcement] {
        announcements.filter {
            !hiddenAnnouncementIDs.contains(
                HiddenContentStore.announcementID($0)
            )
        }
    }

    var hiddenAnnouncementCount: Int {
        announcements.filter {
            hiddenAnnouncementIDs.contains(
                HiddenContentStore.announcementID($0)
            )
        }.count
    }

    func hide(_ assignment: Assignment) {
        hiddenDeadlineIDs.insert(HiddenContentStore.assignmentID(assignment))
        saveHiddenDeadlines()
    }

    func hide(_ quiz: Quiz) {
        hiddenDeadlineIDs.insert(HiddenContentStore.quizID(quiz))
        saveHiddenDeadlines()
    }

    func hide(_ announcement: Announcement) {
        hiddenAnnouncementIDs.insert(
            HiddenContentStore.announcementID(announcement)
        )
        saveHiddenAnnouncements()
    }

    func restoreAssignments(countsOverdueItems: Bool) {
        for assignment in eligibleAssignments(
            countsOverdueItems: countsOverdueItems
        ) {
            hiddenDeadlineIDs.remove(HiddenContentStore.assignmentID(assignment))
        }
        saveHiddenDeadlines()
    }

    func restoreQuizzes(countsOverdueItems: Bool) {
        for quiz in eligibleQuizzes(countsOverdueItems: countsOverdueItems) {
            hiddenDeadlineIDs.remove(HiddenContentStore.quizID(quiz))
        }
        saveHiddenDeadlines()
    }

    func restoreAnnouncements() {
        for announcement in announcements {
            hiddenAnnouncementIDs.remove(
                HiddenContentStore.announcementID(announcement)
            )
        }
        saveHiddenAnnouncements()
    }

    func load() async {
        guard !isLoading, !isLoadingMaterials else { return }
        isLoading = true
        isLoadingMaterials = true
        errorMessage = nil

        await withTaskGroup(of: ContentResult.self) { group in
            group.addTask { [repository, courseID] in
                do {
                    return .assignments(
                        try await repository.fetchAssignments(courseID: courseID)
                    )
                } catch {
                    return .failure(error.localizedDescription)
                }
            }
            group.addTask { [repository, courseID] in
                do {
                    return .quizzes(
                        try await repository.fetchQuizzes(courseID: courseID)
                    )
                } catch {
                    return .failure(error.localizedDescription)
                }
            }
            group.addTask { [repository, courseID] in
                do {
                    return .announcements(
                        try await repository.fetchAnnouncements(courseID: courseID)
                    )
                } catch {
                    return .failure(error.localizedDescription)
                }
            }

            for await result in group {
                switch result {
                case let .assignments(values):
                    assignments = values
                case let .quizzes(values):
                    quizzes = values
                case let .announcements(values):
                    announcements = values
                case let .failure(message):
                    errorMessage = errorMessage ?? message
                }
            }
        }
        isLoading = false

        defer { isLoadingMaterials = false }
        do {
            let result = try await repository.fetchMaterials(courseID: courseID)
            materials = result.materials
            resourcesURL = result.resourcesURL
        } catch {
            errorMessage = errorMessage ?? error.localizedDescription
        }
    }

    func refresh() async {
        await repository.invalidateCaches(courseID: courseID)
        await load()
    }

    func loadAnnouncementBody(id: String) async {
        guard
            !loadingAnnouncementIDs.contains(id),
            let index = announcements.firstIndex(where: { $0.id == id }),
            announcements[index].body.isEmpty
        else {
            return
        }
        loadingAnnouncementIDs.insert(id)
        defer { loadingAnnouncementIDs.remove(id) }
        let old = announcements[index]
        do {
            let body = try await repository.fetchAnnouncementBody(
                courseID: old.courseID,
                announcementID: old.id,
                url: old.tactURL
            )
            announcements[index] = Announcement(
                id: old.id,
                courseID: old.courseID,
                title: old.title,
                body: body,
                publishedAt: old.publishedAt,
                tactURL: old.tactURL
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func eligibleAssignments(
        countsOverdueItems: Bool
    ) -> [Assignment] {
        assignments.filter {
            !$0.isSubmitted && (countsOverdueItems || !$0.isOverdue)
        }
    }

    private func eligibleQuizzes(countsOverdueItems: Bool) -> [Quiz] {
        quizzes.filter {
            !$0.isSubmitted && (countsOverdueItems || !$0.isOverdue)
        }
    }

    private func saveHiddenDeadlines() {
        HiddenContentStore.saveDeadlineIDs(hiddenDeadlineIDs)
    }

    private func saveHiddenAnnouncements() {
        HiddenContentStore.saveAnnouncementIDs(hiddenAnnouncementIDs)
    }

    private enum ContentResult: Sendable {
        case assignments([Assignment])
        case quizzes([Quiz])
        case announcements([Announcement])
        case failure(String)
    }
}
