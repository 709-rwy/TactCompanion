import SwiftUI

struct AnnouncementListView: View {
    @ObservedObject private var viewModel: AnnouncementListViewModel
    @EnvironmentObject private var refreshController: AppRefreshController

    init(viewModel: AnnouncementListViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.announcements.isEmpty {
                ProgressView("お知らせを取得中")
            } else if viewModel.announcements.isEmpty {
                ContentUnavailableView(
                    "お知らせはありません",
                    systemImage: "megaphone",
                    description: Text(
                        viewModel.errorMessage ??
                        "授業のお知らせが新しい順に表示されます。"
                    )
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                    if viewModel.hiddenAnnouncementCount > 0 {
                        Button("非表示のお知らせをすべて戻す") {
                            withAnimation {
                                viewModel.restoreHiddenAnnouncements()
                            }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(viewModel.visibleAnnouncements) { row in
                        InlineAnnouncementRow(
                            row: row,
                            isLoading: viewModel.loadingBodyIDs.contains(
                                row.id
                            ),
                            loadBody: {
                                await viewModel.loadBody(for: row.id)
                            },
                            hide: {
                                withAnimation(.snappy(duration: 0.28)) {
                                    viewModel.hide(row)
                                }
                            }
                        )
                        .padding(10)
                        .background(
                            Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .transition(
                            .scale(scale: 0.05, anchor: .bottomTrailing)
                            .combined(with: .opacity)
                        )
                    }
                }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .refreshable { await viewModel.refresh() }
            }
        }
        .task { await viewModel.load() }
        .onChange(of: refreshController.requestID) { _, _ in
            Task { await viewModel.refresh() }
        }
    }
}

private struct InlineAnnouncementRow: View {
    let row: AnnouncementListViewModel.Row
    let isLoading: Bool
    let loadBody: () async -> Void
    let hide: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggleExpanded) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.announcement.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(row.courseTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(
                        DisplayDateFormatter.dateTime.string(
                            from: row.announcement.publishedAt
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .transaction { transaction in
                transaction.animation = nil
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if isLoading {
                        ProgressView("本文を読み込み中")
                    } else if row.announcement.displayBody.isEmpty {
                        Text("本文を取得できませんでした。")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(row.announcement.displayBody)
                            .textSelection(.enabled)
                    }
                    Divider()
                }
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }

            HStack {
                Button(action: toggleExpanded) {
                    Label(
                        isExpanded ? "閉じる" : "本文を表示",
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: hide) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(row.announcement.title)を非表示")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: isExpanded) { _, expanded in
            guard expanded, row.announcement.body.isEmpty else { return }
            Task { await loadBody() }
        }
    }

    private func toggleExpanded() {
        var transaction = Transaction(
            animation: .snappy(duration: 0.22)
        )
        transaction.disablesAnimations = false
        withTransaction(transaction) {
            isExpanded.toggle()
        }
    }
}
