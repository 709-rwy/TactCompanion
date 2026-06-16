import SwiftUI

struct DeadlineCalendarView: View {
    @StateObject private var viewModel: DeadlineListViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var refreshController: AppRefreshController
    @State private var displayedMonth = Calendar.current.startOfMonth(for: .now)
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)

    init(viewModel: DeadlineListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("期限を取得中")
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        monthHeader
                        weekdayHeader
                        calendarGrid
                        selectedDayDeadlines
                    }
                    .padding()
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
    }

    private var monthHeader: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                .font(.headline)

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .buttonStyle(.borderless)
    }

    private var weekdayHeader: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible()), count: 7),
            spacing: 6
        ) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.caption.bold())
                    .foregroundStyle(
                        index == 0 ? .red : index == 6 ? .blue : .secondary
                    )
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
            spacing: 6
        ) {
            ForEach(monthDates, id: \.self) { date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear
                        .frame(height: 48)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let items = items(on: date)
        let hiddenItems = hiddenItems(on: date)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let isToday = Calendar.current.isDateInToday(date)

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.weight(isToday ? .bold : .regular))

                HStack(spacing: 2) {
                    let dots = Array(items.prefix(hiddenItems.isEmpty ? 3 : 2))
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, item in
                        Circle()
                            .fill(item.kind == .assignment ? Color.orange : Color.red)
                            .frame(width: 5, height: 5)
                    }
                    if !hiddenItems.isEmpty {
                        Circle()
                            .fill(Color(white: 0.22))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var selectedDayDeadlines: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DisplayDateFormatter.date.string(from: selectedDate))
                .font(.headline)

            let selectedItems = items(on: selectedDate)
            let selectedHiddenItems = hiddenItems(on: selectedDate)
            if selectedItems.isEmpty {
                Text("この日に提出期限のある課題・小テストはありません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(selectedItems) { item in
                    InlineDeadlineRow(
                        item: item,
                        urgency: urgency(for: item),
                        settings: settings,
                        dueDateStyle: .timeOnly
                    ) {
                        withAnimation(.snappy(duration: 0.28)) {
                            viewModel.hide(item)
                        }
                    }
                    .padding(10)
                    .background(
                        Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .transition(
                        .scale(scale: 0.05, anchor: .bottomTrailing)
                        .combined(with: .opacity)
                    )
                }
            }

            if !selectedHiddenItems.isEmpty {
                Button {
                    withAnimation(.snappy) {
                        viewModel.restore(selectedHiddenItems)
                    }
                } label: {
                    Label(
                        "この日の非表示項目を戻す（\(selectedHiddenItems.count)件）",
                        systemImage: "arrow.uturn.backward"
                    )
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func hiddenItems(on date: Date) -> [DeadlineItem] {
        viewModel.hiddenItems
            .filter {
                guard let dueDate = $0.dueDate else { return false }
                return Calendar.current.isDate(dueDate, inSameDayAs: date)
            }
            .sorted {
                ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
    }

    private var monthDates: [Date?] {
        let calendar = Calendar.current
        guard
            let range = calendar.range(of: .day, in: .month, for: displayedMonth),
            let firstDay = calendar.date(
                from: calendar.dateComponents([.year, .month], from: displayedMonth)
            )
        else {
            return []
        }

        let leadingEmptyDays = calendar.component(.weekday, from: firstDay) - 1
        let dates = range.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: firstDay)
        }
        return Array(repeating: nil, count: leadingEmptyDays) + dates.map(Optional.some)
    }

    private func items(on date: Date) -> [DeadlineItem] {
        viewModel.itemsExcludingHidden
            .filter {
                guard let dueDate = $0.dueDate else { return false }
                return Calendar.current.isDate(dueDate, inSameDayAs: date)
            }
            .sorted {
                ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
    }

    private func changeMonth(by value: Int) {
        guard let month = Calendar.current.date(
            byAdding: .month,
            value: value,
            to: displayedMonth
        ) else {
            return
        }
        displayedMonth = month
        selectedDate = month
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
