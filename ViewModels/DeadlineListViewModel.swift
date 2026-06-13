import Combine
import Foundation

@MainActor
final class DeadlineListViewModel: ObservableObject {
    @Published private(set) var items: [DeadlineItem] = []
    @Published private(set) var isLoading = false
    @Published var showsOverdue = false
    @Published var errorMessage: String?

    private let repository: any TactRepositoryProtocol
    @Published private var hiddenItemIDs: Set<String>
    private var hiddenContentObserver: NSObjectProtocol?

    init(repository: any TactRepositoryProtocol) {
        self.repository = repository
        hiddenItemIDs = HiddenContentStore.deadlineIDs
        hiddenContentObserver = NotificationCenter.default.addObserver(
            forName: HiddenContentStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hiddenItemIDs = HiddenContentStore.deadlineIDs
            }
        }
    }

    deinit {
        if let hiddenContentObserver {
            NotificationCenter.default.removeObserver(hiddenContentObserver)
        }
    }

    var visibleItems: [DeadlineItem] {
        itemsExcludingHidden.filter { showsOverdue || !$0.isOverdue }
    }

    var itemsExcludingHidden: [DeadlineItem] {
        items.filter { !hiddenItemIDs.contains($0.id) }
    }

    var hiddenItems: [DeadlineItem] {
        items.filter { hiddenItemIDs.contains($0.id) }
    }

    var hiddenItemCount: Int {
        items.filter { hiddenItemIDs.contains($0.id) }.count
    }

    func hide(_ item: DeadlineItem) {
        hiddenItemIDs.insert(item.id)
        saveHiddenItems()
    }

    func restoreHiddenItems() {
        hiddenItemIDs.removeAll()
        saveHiddenItems()
    }

    func restore(_ items: [DeadlineItem]) {
        for item in items {
            hiddenItemIDs.remove(item.id)
        }
        saveHiddenItems()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let courses = try await repository.fetchCourses()
            items = []
            await withTaskGroup(of: [DeadlineItem].self) { group in
                for course in courses {
                    group.addTask { [repository] in
                        async let assignments = try? repository.fetchAssignments(
                            courseID: course.id
                        )
                        async let quizzes = try? repository.fetchQuizzes(
                            courseID: course.id
                        )

                        let assignmentValues = await assignments ?? []
                        let quizValues = await quizzes ?? []

                        let assignmentItems = assignmentValues
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
                            }

                        let quizItems = quizValues
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

                        return assignmentItems + quizItems
                    }
                }

                for await courseItems in group {
                    items.append(contentsOf: courseItems)
                    items.sort {
                        ($0.dueDate ?? .distantFuture, $0.title)
                        <
                        ($1.dueDate ?? .distantFuture, $1.title)
                    }
                }
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await repository.invalidateCaches()
        await load()
    }

    func updateWidgetSnapshot(settings: AppSettings) {
        WidgetSnapshotStore.updateDeadlines(
            items,
            urgentDayCount: settings.urgentDayCount,
            referenceWeekday: settings.referenceWeekday,
            firstBoundaryWeek: settings.firstBoundaryWeek,
            secondBoundaryWeek: settings.secondBoundaryWeek,
            boundaryHour: settings.deadlineBoundaryHour,
            boundaryMinute: settings.deadlineBoundaryMinute
        )
    }

    private func saveHiddenItems() {
        HiddenContentStore.saveDeadlineIDs(hiddenItemIDs)
    }
}
