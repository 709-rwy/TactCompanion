import Combine
import Foundation

@MainActor
final class AnnouncementListViewModel: ObservableObject {
    struct Row: Identifiable, Hashable, Sendable {
        let announcement: Announcement
        let courseTitle: String

        var id: String {
            "\(announcement.courseID)-\(announcement.id)"
        }
    }

    @Published private(set) var announcements: [Row] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingBodyIDs: Set<String> = []
    @Published var errorMessage: String?

    private let repository: any TactRepositoryProtocol
    @Published private var hiddenAnnouncementIDs: Set<String>
    private var hiddenContentObserver: NSObjectProtocol?

    init(repository: any TactRepositoryProtocol) {
        self.repository = repository
        hiddenAnnouncementIDs = HiddenContentStore.announcementIDs
        hiddenContentObserver = NotificationCenter.default.addObserver(
            forName: HiddenContentStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hiddenAnnouncementIDs = HiddenContentStore.announcementIDs
            }
        }
    }

    deinit {
        if let hiddenContentObserver {
            NotificationCenter.default.removeObserver(hiddenContentObserver)
        }
    }

    var visibleAnnouncements: [Row] {
        announcements.filter { !hiddenAnnouncementIDs.contains($0.id) }
    }

    var hiddenAnnouncementCount: Int {
        announcements.filter { hiddenAnnouncementIDs.contains($0.id) }.count
    }

    func hide(_ row: Row) {
        hiddenAnnouncementIDs.insert(row.id)
        saveHiddenAnnouncements()
    }

    func restoreHiddenAnnouncements() {
        hiddenAnnouncementIDs.removeAll()
        saveHiddenAnnouncements()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let courses = try await repository.fetchCourses()
            var loadedRows: [Row] = []
            var failedCourses: [Course] = []

            await withTaskGroup(of: CourseLoadResult.self) { group in
                for course in courses {
                    group.addTask { [repository] in
                        do {
                            let values = try await repository.fetchAnnouncements(
                                courseID: course.id
                            )
                            return .success(
                                values.map {
                                    Row(
                                        announcement: $0,
                                        courseTitle: course.title
                                    )
                                }
                            )
                        } catch {
                            return .failure(course)
                        }
                    }
                }

                for await result in group {
                    switch result {
                    case let .success(rows):
                        loadedRows.append(contentsOf: rows)
                    case let .failure(course):
                        failedCourses.append(course)
                    }
                }
            }

            if !failedCourses.isEmpty {
                await withTaskGroup(of: [Row].self) { group in
                    for course in failedCourses {
                        group.addTask { [repository] in
                            let values = try? await repository.fetchAnnouncements(
                                courseID: course.id
                            )
                            return values?.map {
                                Row(
                                    announcement: $0,
                                    courseTitle: course.title
                                )
                            } ?? []
                        }
                    }
                    for await rows in group {
                        loadedRows.append(contentsOf: rows)
                    }
                }
            }

            announcements = loadedRows.sorted {
                $0.announcement.publishedAt > $1.announcement.publishedAt
            }
            errorMessage = loadedRows.isEmpty && !failedCourses.isEmpty
                ? "一部のお知らせを取得できませんでした。再読み込みしてください。"
                : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await repository.invalidateCaches()
        await load()
    }

    func loadBody(for rowID: String) async {
        guard
            !loadingBodyIDs.contains(rowID),
            let index = announcements.firstIndex(where: { $0.id == rowID }),
            announcements[index].announcement.body.isEmpty
        else {
            return
        }

        loadingBodyIDs.insert(rowID)
        defer { loadingBodyIDs.remove(rowID) }
        let row = announcements[index]
        do {
            let body = try await repository.fetchAnnouncementBody(
                courseID: row.announcement.courseID,
                announcementID: row.announcement.id,
                url: row.announcement.tactURL
            )
            let old = row.announcement
            announcements[index] = Row(
                announcement: Announcement(
                    id: old.id,
                    courseID: old.courseID,
                    title: old.title,
                    body: body,
                    publishedAt: old.publishedAt,
                    tactURL: old.tactURL
                ),
                courseTitle: row.courseTitle
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveHiddenAnnouncements() {
        HiddenContentStore.saveAnnouncementIDs(hiddenAnnouncementIDs)
    }

    private enum CourseLoadResult: Sendable {
        case success([Row])
        case failure(Course)
    }
}
