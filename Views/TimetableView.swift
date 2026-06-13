import SwiftUI

struct TimetableView: View {
    @StateObject private var viewModel: TimetableViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var refreshController: AppRefreshController
    private let selectCourse: (Course) -> Void

    init(
        viewModel: TimetableViewModel,
        selectCourse: @escaping (Course) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.selectCourse = selectCourse
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.courseSummaries.isEmpty {
                ProgressView("時間割を取得中")
            } else if viewModel.courseSummaries.isEmpty {
                ContentUnavailableView(
                    "授業がありません",
                    systemImage: "calendar",
                    description: Text(viewModel.errorMessage ?? "TACTにログインして更新してください。")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Picker("開講期", selection: $viewModel.selectedTerm) {
                            ForEach(availableTerms, id: \.self) { term in
                                Text(term.displayName).tag(term)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        GeometryReader { geometry in
                            let periodWidth: CGFloat = 24
                            let spacing: CGFloat = 3
                            let headerHeight: CGFloat = 22
                            let rowHeight: CGFloat = 92
                            let rowSpacing: CGFloat = 4
                            let availableWidth = geometry.size.width - 16
                            let cellWidth = (
                                availableWidth - periodWidth - spacing * 5
                            ) / 5

                            ZStack(alignment: .topLeading) {
                                ForEach(
                                    Array(viewModel.weekdays.enumerated()),
                                    id: \.element
                                ) { weekdayIndex, weekday in
                                    Text(weekday.shortName)
                                        .font(.caption.bold())
                                        .frame(width: cellWidth, height: headerHeight)
                                        .offset(
                                            x: periodWidth + spacing +
                                                CGFloat(weekdayIndex) *
                                                (cellWidth + spacing)
                                        )
                                }

                                ForEach(Array(viewModel.periods), id: \.self) { period in
                                    let rowIndex = period - viewModel.periods.lowerBound
                                    Text("\(period)")
                                        .font(.caption.bold())
                                        .frame(
                                            width: periodWidth,
                                            height: rowHeight
                                        )
                                        .offset(
                                            y: headerHeight + rowSpacing +
                                                CGFloat(rowIndex) *
                                                (rowHeight + rowSpacing)
                                        )

                                    ForEach(
                                        Array(viewModel.weekdays.enumerated()),
                                        id: \.element
                                    ) { weekdayIndex, weekday in
                                        if viewModel.summary(
                                            weekday: weekday,
                                            period: period
                                        ) == nil {
                                            RoundedRectangle(cornerRadius: 7)
                                                .fill(.quaternary.opacity(0.35))
                                                .frame(
                                                    width: cellWidth,
                                                    height: rowHeight
                                                )
                                                .offset(
                                                    x: periodWidth + spacing +
                                                        CGFloat(weekdayIndex) *
                                                        (cellWidth + spacing),
                                                    y: headerHeight + rowSpacing +
                                                        CGFloat(rowIndex) *
                                                        (rowHeight + rowSpacing)
                                                )
                                        }
                                    }
                                }

                                ForEach(timetableBlocks) { block in
                                    let weekdayIndex =
                                        viewModel.weekdays.firstIndex(
                                            of: block.weekday
                                        ) ?? 0
                                    let rowIndex =
                                        block.startPeriod -
                                        viewModel.periods.lowerBound
                                    let blockHeight =
                                        CGFloat(block.periodCount) * rowHeight +
                                        CGFloat(block.periodCount - 1) * rowSpacing

                                    CourseNavigationCard(
                                        summary: block.summary,
                                        compactWidth: cellWidth,
                                        compactHeight: blockHeight,
                                        selectCourse: selectCourse
                                    )
                                    .offset(
                                        x: periodWidth + spacing +
                                            CGFloat(weekdayIndex) *
                                            (cellWidth + spacing),
                                        y: headerHeight + rowSpacing +
                                            CGFloat(rowIndex) *
                                            (rowHeight + rowSpacing)
                                    )
                                    .zIndex(1)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        .frame(height: CGFloat(viewModel.periods.count) * 96 + 26)

                        if !viewModel.unscheduledCourses.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("曜日・時限未設定")
                                    .font(.headline)

                                ForEach(viewModel.unscheduledCourses) { summary in
                                    CourseNavigationCard(
                                        summary: summary,
                                        usesWideLayout: true,
                                        selectCourse: selectCourse
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await viewModel.refresh(
                        countsOverdueItems: settings.countsOverdueItems
                    )
                }
            }
        }
        .task {
            await viewModel.load(
                countsOverdueItems: settings.countsOverdueItems
            )
        }
        .onChange(of: refreshController.requestID) { _, _ in
            Task {
                await viewModel.refresh(
                    countsOverdueItems: settings.countsOverdueItems
                )
            }
        }
        .onChange(of: settings.countsOverdueItems) { _, value in
            Task { await viewModel.recalculateCounts(countsOverdueItems: value) }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: HiddenContentStore.didChangeNotification
            )
        ) { _ in
            Task {
                await viewModel.recalculateCounts(
                    countsOverdueItems: settings.countsOverdueItems
                )
            }
        }
        .onChange(of: settings.showsOtherSeason) { _, _ in
            normalizeSelectedTerm()
        }
        .alert(
            "読み込みエラー",
            isPresented: Binding(
                get: {
                    viewModel.errorMessage != nil &&
                    !viewModel.courseSummaries.isEmpty
                },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var timetableBlocks: [TimetableBlock] {
        viewModel.weekdays.flatMap { weekday -> [TimetableBlock] in
            var blocks: [TimetableBlock] = []
            for summary in viewModel.displayedSummaries {
                let periods = summary.course.meetings
                    .filter { $0.weekday == weekday }
                    .map(\.period)
                    .sorted()
                guard var start = periods.first else { continue }
                var previous = start

                for period in periods.dropFirst() {
                    if period == previous + 1 {
                        previous = period
                        continue
                    }
                    blocks.append(
                        TimetableBlock(
                            summary: summary,
                            weekday: weekday,
                            startPeriod: start,
                            endPeriod: previous
                        )
                    )
                    start = period
                    previous = period
                }
                blocks.append(
                    TimetableBlock(
                        summary: summary,
                        weekday: weekday,
                        startPeriod: start,
                        endPeriod: previous
                    )
                )
            }
            return blocks
        }
    }

    private var availableTerms: [Course.Term] {
        settings.showsOtherSeason
            ? Course.Term.allCases
            : TimetableViewModel.currentSeasonTerms
    }

    private func normalizeSelectedTerm() {
        guard !availableTerms.contains(viewModel.selectedTerm) else { return }
        viewModel.selectedTerm = availableTerms[0]
    }
}

private struct TimetableBlock: Identifiable {
    let summary: CourseActivitySummary
    let weekday: Course.Weekday
    let startPeriod: Int
    let endPeriod: Int

    var id: String {
        "\(summary.course.id)-\(weekday.rawValue)-\(startPeriod)"
    }

    var periodCount: Int {
        endPeriod - startPeriod + 1
    }
}

private struct CourseNavigationCard: View {
    let summary: CourseActivitySummary
    var usesWideLayout = false
    var compactWidth: CGFloat?
    var compactHeight: CGFloat = 92
    let selectCourse: (Course) -> Void

    var body: some View {
        Button {
            selectCourse(summary.course)
        } label: {
            VStack(alignment: .leading, spacing: usesWideLayout ? 8 : 3) {
                Text(summary.course.title)
                    .font(usesWideLayout ? .subheadline.weight(.semibold) : .caption2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(usesWideLayout ? 2 : 4)
                    .minimumScaleFactor(0.7)

                if let room = summary.course.room {
                    Text(room)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Group {
                    if !usesWideLayout, let compactWidth, compactWidth < 72 {
                        VStack(alignment: .leading, spacing: 1) {
                            activityCounts
                        }
                    } else {
                        HStack(spacing: usesWideLayout ? 10 : 3) {
                            activityCounts
                        }
                    }
                }
            }
            .padding(usesWideLayout ? 10 : 4)
            .frame(
                width: usesWideLayout ? nil : compactWidth,
                height: usesWideLayout ? 110 : compactHeight,
                alignment: .topLeading
            )
            .frame(maxWidth: usesWideLayout ? .infinity : nil)
            .background(
                Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var activityCounts: some View {
        ActivityCount(
            systemImage: "doc.text",
            count: summary.pendingAssignmentCount,
            tint: .orange
        )
        ActivityCount(
            systemImage: "checklist",
            count: summary.pendingQuizCount,
            tint: .red
        )
        ActivityCount(
            systemImage: "megaphone",
            count: summary.announcementCount,
            tint: .blue
        )
    }
}

private struct ActivityCount: View {
    let systemImage: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
                .frame(width: 10, alignment: .center)
            Text("\(count)")
                .monospacedDigit()
                .frame(width: 12, alignment: .trailing)
        }
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(count > 0 ? tint : .secondary)
    }
}
