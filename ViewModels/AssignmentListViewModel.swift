import Combine
import Foundation

@MainActor
final class AssignmentListViewModel: ObservableObject {
    @Published private(set) var assignments: [Assignment] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let courseID: String
    private let repository: any TactRepositoryProtocol

    init(courseID: String, repository: any TactRepositoryProtocol) {
        self.courseID = courseID
        self.repository = repository
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            assignments = try await repository.fetchAssignments(courseID: courseID)
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await repository.invalidateCaches(courseID: courseID)
        await load()
    }
}
