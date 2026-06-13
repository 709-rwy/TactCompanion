import SwiftUI

struct DeadlineListView: View {
    @StateObject private var viewModel: DeadlineListViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var refreshController: AppRefreshController

    init(viewModel: DeadlineListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("期限を取得中")
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "未提出の項目はありません",
                    systemImage: "checkmark.circle",
                    description: Text(
                        viewModel.errorMessage ??
                        "未提出の課題と小テストが期限順に表示されます。"
                    )
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(
                                "期限切れも表示",
                                isOn: $viewModel.showsOverdue
                            )

                            if viewModel.hiddenItemCount > 0 {
                                Button("非表示項目をすべて戻す") {
                                    viewModel.restoreHiddenItems()
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                        if viewModel.visibleItems.isEmpty {
                            Text("現在の表示条件に該当する項目はありません。")
                                .foregroundStyle(.secondary)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .padding(.vertical, 24)
                        } else {
                            ForEach(viewModel.visibleItems) { item in
                                InlineDeadlineRow(
                                    item: item,
                                    urgency: urgency(for: item),
                                    settings: settings
                                ) {
                                    withAnimation(.snappy(duration: 0.28)) {
                                        viewModel.hide(item)
                                    }
                                }
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .refreshable {
                    await viewModel.refresh()
                    viewModel.updateWidgetSnapshot(settings: settings)
                }
            }
        }
        .task {
            await viewModel.load()
            viewModel.updateWidgetSnapshot(settings: settings)
        }
        .onChange(of: refreshController.requestID) { _, _ in
            Task {
                await viewModel.refresh()
                viewModel.updateWidgetSnapshot(settings: settings)
            }
        }
        .onChange(of: widgetConfiguration) { _, _ in
            viewModel.updateWidgetSnapshot(settings: settings)
        }
    }

    private var widgetConfiguration: String {
        [
            settings.urgentDayCount,
            settings.referenceWeekday,
            settings.firstBoundaryWeek,
            settings.secondBoundaryWeek,
            settings.deadlineBoundaryHour,
            settings.deadlineBoundaryMinute
        ]
        .map(String.init)
        .joined(separator: "-")
    }

    private func urgency(for item: DeadlineItem) -> DeadlineItem.Urgency {
        item.urgency(
            urgentDayCount: settings.urgentDayCount,
            referenceWeekday: settings.referenceWeekday,
            firstBoundaryWeek: settings.firstBoundaryWeek,
            secondBoundaryWeek: settings.secondBoundaryWeek,
            boundaryHour: settings.deadlineBoundaryHour,
            boundaryMinute: settings.deadlineBoundaryMinute
        )
    }
}

struct InlineDeadlineRow: View {
    enum DueDateStyle {
        case dateAndTime
        case timeOnly
    }

    enum PresentationStyle {
        case standard
        case courseDetail
    }

    private struct BrowserDestination: Identifiable {
        let id = UUID()
        let url: URL
    }

    let item: DeadlineItem
    let urgency: DeadlineItem.Urgency
    let settings: AppSettings
    let hide: () -> Void
    private let dueDateStyle: DueDateStyle
    private let presentationStyle: PresentationStyle
    private let renderedDetails: String?
    private let detailLinks: [URL]
    @State private var isExpanded = false
    @State private var browserDestination: BrowserDestination?

    init(
        item: DeadlineItem,
        urgency: DeadlineItem.Urgency,
        settings: AppSettings,
        dueDateStyle: DueDateStyle = .dateAndTime,
        presentationStyle: PresentationStyle = .standard,
        hide: @escaping () -> Void
    ) {
        self.item = item
        self.urgency = urgency
        self.settings = settings
        self.dueDateStyle = dueDateStyle
        self.presentationStyle = presentationStyle
        self.hide = hide
        renderedDetails = item.displayDetails
        detailLinks = item.detailLinks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggleExpanded) {
                summary
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .transaction { transaction in
                transaction.animation = nil
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let details = renderedDetails,
                       !details.isEmpty {
                        Text(details)
                            .foregroundStyle(
                                presentationStyle == .courseDetail
                                    ? Color.primary
                                    : Color.primary
                            )
                            .textSelection(.enabled)
                    } else if let availableFrom = item.availableFrom {
                        Label(
                            "公開: \(DisplayDateFormatter.dateTime.string(from: availableFrom))",
                            systemImage: "clock"
                        )
                        .font(.subheadline)
                    } else {
                        Text("アプリ内で表示できる詳細情報はありません。")
                            .foregroundStyle(
                                presentationStyle == .courseDetail
                                    ? Color.secondary
                                    : Color.secondary
                            )
                    }

                    if !detailLinks.isEmpty {
                        Divider()
                        ForEach(detailLinks, id: \.self) { url in
                            Button {
                                browserDestination = BrowserDestination(url: url)
                            } label: {
                                Label(
                                    linkTitle(for: url),
                                    systemImage: "link"
                                )
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                    }
                    Divider()
                }
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }

            HStack(spacing: presentationStyle == .courseDetail ? 14 : 18) {
                Button(action: toggleExpanded) {
                    DeadlineActionLabel(
                        title: isExpanded ? "閉じる" : "内容を表示",
                        systemImage: isExpanded
                            ? "chevron.up"
                            : "chevron.down",
                        foregroundColor: actionColor
                    )
                }
                .buttonStyle(.plain)

                Button {
                    browserDestination = BrowserDestination(url: item.tactURL)
                } label: {
                    DeadlineActionLabel(
                        title: "TACTで開く",
                        systemImage: "safari",
                        foregroundColor: actionColor
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(action: hide) {
                    Image(systemName: "trash")
                        .foregroundStyle(actionColor)
                        .padding(7)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(item.title)を非表示")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sheet(item: $browserDestination) { destination in
            NavigationStack {
                TactWebDestination(
                    url: destination.url,
                    title: destination.url == item.tactURL
                        ? item.title
                        : destination.url.host ?? "リンク"
                )
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            if presentationStyle == .standard {
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(item.kind == .assignment ? .orange : .red)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(
                        presentationStyle == .courseDetail
                            ? .subheadline.weight(.semibold)
                            : .headline
                    )
                    .foregroundStyle(
                        presentationStyle == .courseDetail
                            ? Color.primary
                            : Color.primary
                    )

                if presentationStyle == .standard {
                    Text(item.courseTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let dueDate = item.dueDate {
                    HStack(spacing: 6) {
                        Label(
                            formattedDueDate(dueDate),
                            systemImage: "calendar.badge.clock"
                        )
                        .font(.caption)
                        .foregroundStyle(urgency.color)

                        if let label = urgencyLabel {
                            Text(label)
                                .font(.caption2.bold())
                                .foregroundStyle(urgency.color)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    urgency.color.opacity(0.12),
                                    in: Capsule()
                                )
                        }
                    }
                } else {
                    Label(
                        "期限未設定",
                        systemImage: "calendar.badge.questionmark"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if presentationStyle == .standard {
                Text(item.kind.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private var urgencyLabel: String? {
        switch urgency {
        case .overdue:
            return "期限切れ"
        case .dueSoon, .beforeFirstBoundary, .beforeSecondBoundary:
            return item.remainingTimeLabel()
        case .later, .noDeadline:
            return nil
        }
    }

    private var actionColor: Color {
        .secondary
    }

    private func linkTitle(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host
        }
        return "リンクを開く"
    }

    private func formattedDueDate(_ date: Date) -> String {
        switch dueDateStyle {
        case .dateAndTime:
            return DisplayDateFormatter.dateTime.string(from: date)
        case .timeOnly:
            return date.formatted(date: .omitted, time: .shortened)
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

struct DeadlineActionLabel: View {
    let title: String
    let systemImage: String
    var foregroundColor: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.caption)
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Color.secondary.opacity(0.11),
            in: Capsule()
        )
        .contentShape(Capsule())
    }
}

extension DeadlineItem.Urgency {
    var color: Color {
        switch self {
        case .overdue:
            return .red
        case .dueSoon:
            return .orange
        case .beforeFirstBoundary:
            return .yellow
        case .beforeSecondBoundary:
            return .green
        case .later, .noDeadline:
            return .primary
        }
    }
}
