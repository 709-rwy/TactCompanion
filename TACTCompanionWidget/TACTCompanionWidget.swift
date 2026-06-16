import AppIntents
import SwiftUI
import WidgetKit

private let appGroupID = "group.jp.ac.thers.TACTCompanion"
private let snapshotKey = "widgetSnapshot"

private struct SharedCourse: Codable {
    let id: String
    let title: String
    let weekday: Int?
    let period: Int?
    let terms: [String]
}

private struct SharedDeadline: Codable, Identifiable {
    let id: String
    let title: String
    let courseTitle: String
    let dueDate: Date?
    let kind: String
    let urgency: String?
}

private struct SharedSnapshot: Codable {
    var courses: [SharedCourse] = []
    var deadlines: [SharedDeadline] = []
    var selectedTerm = "春1期"
    var updatedAt = Date.now
}

enum WidgetDisplay: String, AppEnum {
    case deadlines
    case calendar

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "表示内容"
    )
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .deadlines: "提出期限リスト",
        .calendar: "期限カレンダー"
    ]
}

struct TACTWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "表示内容"
    static let description = IntentDescription(
        "提出期限リストまたは期限カレンダーから選択します。"
    )

    @Parameter(title: "表示内容", default: .deadlines)
    var display: WidgetDisplay
}

private struct TACTWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: TACTWidgetConfiguration
    let snapshot: SharedSnapshot
}

private struct TACTWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TACTWidgetEntry {
        TACTWidgetEntry(
            date: .now,
            configuration: TACTWidgetConfiguration(),
            snapshot: sampleSnapshot
        )
    }

    func snapshot(
        for configuration: TACTWidgetConfiguration,
        in context: Context
    ) async -> TACTWidgetEntry {
        TACTWidgetEntry(
            date: .now,
            configuration: configuration,
            snapshot: loadSnapshot() ?? sampleSnapshot
        )
    }

    func timeline(
        for configuration: TACTWidgetConfiguration,
        in context: Context
    ) async -> Timeline<TACTWidgetEntry> {
        let entry = TACTWidgetEntry(
            date: .now,
            configuration: configuration,
            snapshot: loadSnapshot() ?? SharedSnapshot()
        )
        let nextUpdate = Calendar.current.date(
            byAdding: .minute,
            value: 30,
            to: .now
        ) ?? .now.addingTimeInterval(1_800)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func loadSnapshot() -> SharedSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: snapshotKey)
        else {
            return nil
        }
        return try? JSONDecoder().decode(SharedSnapshot.self, from: data)
    }

    private var sampleSnapshot: SharedSnapshot {
        SharedSnapshot(
            courses: [
                SharedCourse(
                    id: "1",
                    title: "授業名",
                    weekday: 2,
                    period: 1,
                    terms: ["春1期"]
                )
            ],
            deadlines: [
                SharedDeadline(
                    id: "1",
                    title: "課題",
                    courseTitle: "授業名",
                    dueDate: .now.addingTimeInterval(86_400),
                    kind: "課題",
                    urgency: "orange"
                )
            ],
            selectedTerm: "春1期"
        )
    }
}

private struct TACTWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TACTWidgetEntry

    var body: some View {
        Group {
            switch entry.configuration.display {
            case .deadlines:
                DeadlineWidgetView(
                    deadlines: entry.snapshot.deadlines,
                    compact: family == .systemSmall
                )
            case .calendar:
                CalendarWidgetView(deadlines: entry.snapshot.deadlines)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

private struct DeadlineWidgetView: View {
    let deadlines: [SharedDeadline]
    let compact: Bool

    private var upcoming: [SharedDeadline] {
        deadlines
            .filter { ($0.dueDate ?? .distantFuture) >= .now }
            .sorted {
                ($0.dueDate ?? .distantFuture) <
                    ($1.dueDate ?? .distantFuture)
            }
    }

    var body: some View {
        WidgetPanel(
            title: "提出期限",
            systemImage: "clock"
        ) {
            VStack(alignment: .leading, spacing: 5) {
                if upcoming.isEmpty {
                    emptyView("直近の期限はありません")
                } else {
                    ForEach(Array(upcoming.prefix(compact ? 3 : 5))) { item in
                        HStack(spacing: 8) {
                            Image(
                                systemName: item.kind == "小テスト"
                                    ? "checklist"
                                    : "doc.text"
                            )
                            .foregroundStyle(
                                item.kind == "小テスト" ? .red : .orange
                            )
                            .frame(width: 18)

                            Circle()
                                .fill(urgencyColor(item.urgency))
                                .frame(width: 7, height: 7)

                            if let dueDate = item.dueDate {
                                ViewThatFits(in: .horizontal) {
                                    Text(widgetDateTime.string(from: dueDate))
                                    Text(widgetDate.string(from: dueDate))
                                }
                                .font(.caption.monospacedDigit())
                                .lineLimit(1)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(
                            Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }

    private func urgencyColor(_ value: String?) -> Color {
        switch value {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        default: return .clear
        }
    }
}

private struct CalendarWidgetView: View {
    let deadlines: [SharedDeadline]

    private let calendar = Calendar.current

    var body: some View {
        WidgetPanel(
            title: "カレンダー",
            systemImage: "calendar"
        ) {
            VStack(spacing: 3) {
                Text(displayedMonthTitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 2),
                        count: 7
                    ),
                    spacing: 3
                ) {
                    ForEach(
                        ["日", "月", "火", "水", "木", "金", "土"],
                        id: \.self
                    ) {
                        Text($0).font(.system(size: 8, weight: .bold))
                    }
                    ForEach(
                        Array(displayedDates.enumerated()),
                        id: \.offset
                    ) { _, date in
                        VStack(spacing: 1) {
                            Text("\(calendar.component(.day, from: date))")
                                .font(
                                    .system(
                                        size: 9,
                                        weight: isToday(date)
                                            ? .bold
                                            : .regular
                                    )
                                )
                                .foregroundStyle(
                                    isToday(date)
                                        ? Color.white
                                        : isInStartingMonth(date)
                                            ? Color.primary
                                            : Color.secondary
                                )
                                .frame(width: 16, height: 16)
                                .background {
                                    if isToday(date) {
                                        Circle().fill(Color.red)
                                    }
                                }
                            Circle()
                                .fill(
                                    hasDeadline(on: date)
                                        ? Color.orange
                                        : .clear
                                )
                                .frame(width: 3, height: 3)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }

    private var displayedDates: [Date] {
        guard let start = startOfCurrentWeek else { return [] }
        return (0..<21).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private var startOfCurrentWeek: Date? {
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        return calendar.date(
            byAdding: .day,
            value: -(weekday - 1),
            to: today
        )
    }

    private var displayedMonthTitle: String {
        guard
            let first = displayedDates.first,
            let last = displayedDates.last
        else {
            return widgetMonth.string(from: .now)
        }
        if calendar.isDate(first, equalTo: last, toGranularity: .month) {
            return widgetMonth.string(from: first)
        }
        return "\(widgetMonth.string(from: first))-\(widgetMonthOnly.string(from: last))"
    }

    private func isInStartingMonth(_ date: Date) -> Bool {
        guard let first = displayedDates.first else { return true }
        return calendar.isDate(
            date,
            equalTo: first,
            toGranularity: .month
        )
    }

    private func hasDeadline(on date: Date) -> Bool {
        deadlines.contains {
            guard let dueDate = $0.dueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: date)
        }
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }
}

private struct WidgetPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.black)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private func emptyView(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
}

private let widgetDateTime: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "yy/MM/dd HH:mm"
    return formatter
}()

private let widgetDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "yy/MM/dd"
    return formatter
}()

private let widgetMonth: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "yy年MM月"
    return formatter
}()

private let widgetMonthOnly: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "MM月"
    return formatter
}()

struct TACTCompanionWidget: Widget {
    let kind = "TACTCompanionWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: TACTWidgetConfiguration.self,
            provider: TACTWidgetProvider()
        ) { entry in
            TACTWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("TACT Companion")
        .description("提出期限リストまたは期限カレンダーを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct TACTCompanionWidgetBundle: WidgetBundle {
    var body: some Widget {
        TACTCompanionWidget()
    }
}
