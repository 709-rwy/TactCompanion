import SwiftUI

struct MainTabView: View {
    private enum Tab: Int, CaseIterable {
        case timetable
        case deadlines
        case calendar
        case announcements

        var title: String {
            switch self {
            case .timetable: return "時間割"
            case .deadlines: return "提出期限"
            case .calendar: return "カレンダー"
            case .announcements: return "お知らせ"
            }
        }

        var systemImage: String {
            switch self {
            case .timetable: return "calendar"
            case .deadlines: return "clock"
            case .calendar: return "calendar.badge.clock"
            case .announcements: return "megaphone"
            }
        }
    }

    private let repository: any TactRepositoryProtocol
    private let authenticationViewModel: AuthenticationViewModel
    private let notificationService: DeadlineNotificationService
    @EnvironmentObject private var refreshController: AppRefreshController
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var timetableViewModel: TimetableViewModel
    @StateObject private var announcementViewModel: AnnouncementListViewModel
    @State private var selectedTab = Tab.timetable
    @State private var transitionDirection = 1
    @State private var showsSettings = false
    @State private var selectedCourse: Course?

    init(
        repository: any TactRepositoryProtocol,
        authenticationViewModel: AuthenticationViewModel
    ) {
        self.repository = repository
        self.authenticationViewModel = authenticationViewModel
        self.notificationService = DeadlineNotificationService(
            repository: repository
        )
        _timetableViewModel = StateObject(
            wrappedValue: TimetableViewModel(repository: repository)
        )
        _announcementViewModel = StateObject(
            wrappedValue: AnnouncementListViewModel(repository: repository)
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if showsAppChrome {
                    fixedHeader
                }

                ZStack {
                    selectedContent
                        .id(selectedTab)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(
                    TabContentClippingModifier(
                        isEnabled: showsAppChrome
                    )
                )

                if showsAppChrome {
                    bottomTabs
                }
            }

            if let course = selectedCourse {
                NavigationStack {
                    CourseDetailView(
                        course: course,
                        viewModel: CourseDetailViewModel(
                            courseID: course.id,
                            repository: repository
                        ),
                        onDismiss: dismissCourse
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: dismissCourse) {
                                Label("閉じる", systemImage: "xmark")
                            }
                        }
                    }
                }
                .background(Color(.systemBackground))
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .background(
            Color.secondary.opacity(0.04)
                .ignoresSafeArea()
        )
        .highPriorityGesture(
            DragGesture(minimumDistance: 45)
                .onEnded { value in
                    guard
                        selectedCourse == nil,
                        abs(value.translation.width) >
                            abs(value.translation.height) * 1.4,
                        abs(value.translation.width) > 70
                    else {
                        return
                    }
                    moveTab(forward: value.translation.width < 0)
                }
        )
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                SettingsView {
                    showsSettings = false
                    await authenticationViewModel.logout()
                }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") {
                                showsSettings = false
                            }
                        }
                    }
                }
        }
        .task(id: notificationConfiguration) {
            guard
                !timetableViewModel.isLoading,
                !timetableViewModel.courseSummaries.isEmpty
            else {
                return
            }
            await notificationService.update(
                configuration: notificationConfiguration
            )
        }
        .onChange(of: timetableViewModel.isLoading) { _, isLoading in
            guard !isLoading, !timetableViewModel.courseSummaries.isEmpty else {
                return
            }
            Task {
                await notificationService.update(
                    configuration: notificationConfiguration
                )
            }
        }
        .task {
            await announcementViewModel.load()
        }
    }

    private var showsAppChrome: Bool {
        true
    }

    private var notificationConfiguration:
        DeadlineNotificationService.Configuration {
        .init(
            isEnabled: settings.deadlineNotificationsEnabled,
            urgentDayCount: settings.urgentDayCount,
            referenceWeekday: settings.referenceWeekday,
            firstBoundaryWeek: settings.firstBoundaryWeek,
            secondBoundaryWeek: settings.secondBoundaryWeek,
            boundaryHour: settings.deadlineBoundaryHour,
            boundaryMinute: settings.deadlineBoundaryMinute,
            notificationHour: settings.notificationHour,
            notificationMinute: settings.notificationMinute
        )
    }

    private var fixedHeader: some View {
        HStack {
            Text(selectedTab.title)
                .font(.system(size: 30, weight: .bold))

            Spacer()

            HStack(spacing: 8) {
                headerButton(
                    systemImage: "arrow.clockwise",
                    accessibilityLabel: "再読み込み"
                ) {
                    refreshController.requestRefresh()
                }
                headerButton(
                    systemImage: "gearshape",
                    accessibilityLabel: "設定"
                ) {
                    showsSettings = true
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .frame(height: 72)
        .background(.bar)
    }

    private func headerButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.black, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var bottomTabs: some View {
        HStack {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    select(tab)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemImage)
                        Text(tab.title)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(
                        selectedTab == tab ? Color.accentColor : Color.secondary
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 7)
        .padding(.bottom, 4)
        .background(.bar)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .timetable:
            NavigationStack {
                TimetableView(
                    viewModel: timetableViewModel
                ) { course in
                    withAnimation(.smooth(duration: 0.32)) {
                        selectedCourse = course
                    }
                }
            }
        case .deadlines:
            NavigationStack {
                DeadlineListView(
                    viewModel: DeadlineListViewModel(repository: repository)
                )
            }
        case .calendar:
            NavigationStack {
                DeadlineCalendarView(
                    viewModel: DeadlineListViewModel(repository: repository)
                )
            }
        case .announcements:
            NavigationStack {
                AnnouncementListView(
                    viewModel: announcementViewModel
                )
            }
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: transitionDirection > 0 ? .trailing : .leading),
            removal: .move(edge: transitionDirection > 0 ? .leading : .trailing)
        )
    }

    private func select(_ tab: Tab) {
        guard tab != selectedTab else { return }
        transitionDirection = tab.rawValue > selectedTab.rawValue ? 1 : -1
        withAnimation(.smooth(duration: 0.32)) {
            selectedTab = tab
        }
    }

    private func moveTab(forward: Bool) {
        transitionDirection = forward ? 1 : -1
        let count = Tab.allCases.count
        let offset = forward ? 1 : -1
        let nextIndex = (selectedTab.rawValue + offset + count) % count
        guard let nextTab = Tab(rawValue: nextIndex) else { return }
        withAnimation(.smooth(duration: 0.32)) {
            selectedTab = nextTab
        }
    }

    private func dismissCourse() {
        withAnimation(.smooth(duration: 0.32)) {
            selectedCourse = nil
        }
    }
}

private struct TabContentClippingModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.clipped()
        } else {
            content
        }
    }
}
