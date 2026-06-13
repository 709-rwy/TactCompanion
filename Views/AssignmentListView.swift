import SwiftUI

struct AssignmentListView: View {
    @StateObject private var viewModel: AssignmentListViewModel

    init(viewModel: AssignmentListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.assignments.isEmpty {
                ProgressView()
            } else if viewModel.assignments.isEmpty {
                ContentUnavailableView(
                    "課題はありません",
                    systemImage: "checkmark.circle"
                )
            } else {
                List(viewModel.assignments) { assignment in
                    NavigationLink {
                        TactWebDestination(
                            url: assignment.tactURL,
                            title: assignment.title
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(assignment.title)
                                .font(.headline)
                            if let dueDate = assignment.dueDate {
                                Label(
                                    DisplayDateFormatter.dateTime.string(from: dueDate),
                                    systemImage: "calendar.badge.clock"
                                )
                                .font(.caption)
                                .foregroundStyle(assignment.isOverdue ? .red : .secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .refreshable { await viewModel.refresh() }
            }
        }
        .navigationTitle("課題")
        .task { await viewModel.load() }
    }
}
