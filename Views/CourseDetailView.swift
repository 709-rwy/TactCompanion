import SwiftUI

struct CourseDetailView: View {
    let course: Course
    @StateObject private var viewModel: CourseDetailViewModel
    @EnvironmentObject private var settings: AppSettings
    let onDismiss: () -> Void

    init(
        course: Course,
        viewModel: CourseDetailViewModel,
        onDismiss: @escaping () -> Void
    ) {
        self.course = course
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.04)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailSection("授業情報") {
                        LabeledContent("授業名", value: course.title)
                        Divider()
                        NavigationLink {
                            TactWebDestination(
                                url: course.tactURL,
                                title: course.title
                            )
                        } label: {
                            Label("TACTで授業を開く", systemImage: "safari")
                        }
                        if let instructorName = course.instructorName {
                            Divider()
                            LabeledContent("担当", value: instructorName)
                        }
                        if let room = course.room {
                            Divider()
                            LabeledContent("教室", value: room)
                        }
                    }

                    detailSection("コンテンツ") {
                        DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            let assignments = viewModel.visibleAssignments(
                                countsOverdueItems: settings.countsOverdueItems
                            )
                            if viewModel.isLoading && assignments.isEmpty {
                                ProgressView("課題を読み込み中")
                            } else if assignments.isEmpty {
                                Text("未提出課題はありません")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(assignments) { assignment in
                                    deletableAssignmentRow(assignment)
                                        .padding(10)
                                        .background(
                                            Color.secondary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 14)
                                        )
                                }
                            }

                            let hiddenCount = viewModel.hiddenAssignmentCount(
                                countsOverdueItems: settings.countsOverdueItems
                            )
                            if hiddenCount > 0 {
                                Button("非表示の課題を戻す（\(hiddenCount)件）") {
                                    withAnimation(.snappy) {
                                        viewModel.restoreAssignments(
                                            countsOverdueItems: settings.countsOverdueItems
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        let count = viewModel.visibleAssignments(
                            countsOverdueItems: settings.countsOverdueItems
                        ).count
                        Label(
                            "未提出課題 \(count)件",
                            systemImage: "doc.text"
                        )
                    }

                    Divider()

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            let quizzes = viewModel.visibleQuizzes(
                                countsOverdueItems: settings.countsOverdueItems
                            )
                            if viewModel.isLoading && quizzes.isEmpty {
                                ProgressView("小テストを読み込み中")
                            } else if quizzes.isEmpty {
                                Text("未提出小テストはありません")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(quizzes) { quiz in
                                    deletableQuizRow(quiz)
                                        .padding(10)
                                        .background(
                                            Color.secondary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 14)
                                        )
                                }
                            }

                            let hiddenCount = viewModel.hiddenQuizCount(
                                countsOverdueItems: settings.countsOverdueItems
                            )
                            if hiddenCount > 0 {
                                Button("非表示の小テストを戻す（\(hiddenCount)件）") {
                                    withAnimation(.snappy) {
                                        viewModel.restoreQuizzes(
                                            countsOverdueItems: settings.countsOverdueItems
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        let count = viewModel.visibleQuizzes(
                            countsOverdueItems: settings.countsOverdueItems
                        ).count
                        Label(
                            "未提出小テスト \(count)件",
                            systemImage: "checklist"
                        )
                    }

                    Divider()

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            if viewModel.isLoading &&
                                viewModel.visibleAnnouncements.isEmpty {
                                ProgressView("お知らせを読み込み中")
                            } else if viewModel.visibleAnnouncements.isEmpty {
                                Text("お知らせはありません")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(
                                    viewModel.visibleAnnouncements
                                ) { announcement in
                                    deletableAnnouncementRow(announcement)
                                        .padding(10)
                                        .background(
                                            Color.secondary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 14)
                                        )
                                }
                            }

                            if viewModel.hiddenAnnouncementCount > 0 {
                                Button(
                                    "非表示のお知らせを戻す（\(viewModel.hiddenAnnouncementCount)件）"
                                ) {
                                    withAnimation(.snappy) {
                                        viewModel.restoreAnnouncements()
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Label(
                            "お知らせ \(viewModel.visibleAnnouncements.count)件",
                            systemImage: "megaphone"
                        )
                        }
                    }

                    detailSection("授業資料") {
                        if viewModel.isLoadingMaterials &&
                            viewModel.materials.isEmpty {
                            ProgressView("授業資料を読み込み中")
                        } else if viewModel.materials.isEmpty {
                            NavigationLink {
                                TactWebDestination(
                                    url: viewModel.resourcesURL ?? course.tactURL,
                                    title: "\(course.title) 資料"
                                )
                            } label: {
                                Label(
                                    viewModel.resourcesURL == nil
                                        ? "TACTの授業ページから探す"
                                        : "TACTの資料一覧を開く",
                                    systemImage: "folder"
                                )
                            }
                        } else {
                            ForEach(viewModel.materials) { material in
                                MaterialDisclosureRow(material: material)
                                    .padding(.vertical, 2)
                                Divider()
                            }

                            if let resourcesURL = viewModel.resourcesURL {
                                NavigationLink {
                                    TactWebDestination(
                                        url: resourcesURL,
                                        title: "\(course.title) 資料"
                                    )
                                } label: {
                                    Label(
                                        "資料一覧をTACTで開く",
                                        systemImage: "folder"
                                    )
                                }
                            }
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                Color.red.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard
                        value.translation.width >= 90,
                        abs(value.translation.width) >
                            abs(value.translation.height) * 1.3
                    else {
                        return
                    }
                    onDismiss()
                }
        )
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deletableAssignmentRow(_ assignment: Assignment) -> some View {
        InlineDeadlineRow(
            item: DeadlineItem(
                id: HiddenContentStore.assignmentID(assignment),
                courseID: assignment.courseID,
                courseTitle: course.title,
                title: assignment.title,
                dueDate: assignment.dueDate,
                kind: .assignment,
                isOverdue: assignment.isOverdue,
                tactURL: assignment.tactURL,
                details: assignment.instructions,
                availableFrom: nil
            ),
            urgency: urgency(dueDate: assignment.dueDate),
            settings: settings,
            presentationStyle: .courseDetail
        ) {
            withAnimation(.snappy(duration: 0.28)) {
                viewModel.hide(assignment)
            }
        }
    }

    private func deletableQuizRow(_ quiz: Quiz) -> some View {
        InlineDeadlineRow(
            item: DeadlineItem(
                id: HiddenContentStore.quizID(quiz),
                courseID: quiz.courseID,
                courseTitle: course.title,
                title: quiz.title,
                dueDate: quiz.dueDate,
                kind: .quiz,
                isOverdue: quiz.isOverdue,
                tactURL: quiz.tactURL,
                details: nil,
                availableFrom: quiz.availableFrom
            ),
            urgency: urgency(dueDate: quiz.dueDate),
            settings: settings,
            presentationStyle: .courseDetail
        ) {
            withAnimation(.snappy(duration: 0.28)) {
                viewModel.hide(quiz)
            }
        }
    }

    private func urgency(dueDate: Date?) -> DeadlineItem.Urgency {
        DeadlineItem(
            id: "",
            courseID: course.id,
            courseTitle: course.title,
            title: "",
            dueDate: dueDate,
            kind: .assignment,
            isOverdue: dueDate.map { $0 < .now } ?? false,
            tactURL: course.tactURL,
            details: nil,
            availableFrom: nil
        ).urgency(
            urgentDayCount: settings.urgentDayCount,
            referenceWeekday: settings.referenceWeekday,
            firstBoundaryWeek: settings.firstBoundaryWeek,
            secondBoundaryWeek: settings.secondBoundaryWeek,
            boundaryHour: settings.deadlineBoundaryHour,
            boundaryMinute: settings.deadlineBoundaryMinute
        )
    }

    private func hideAnnouncement(_ announcement: Announcement) {
        withAnimation(.snappy(duration: 0.28)) {
            viewModel.hide(announcement)
        }
    }

    private func deletableAnnouncementRow(
        _ announcement: Announcement
    ) -> some View {
        CourseAnnouncementRow(
            announcement: announcement,
            isLoading: viewModel.loadingAnnouncementIDs
                .contains(announcement.id),
            loadBody: {
                await viewModel.loadAnnouncementBody(id: announcement.id)
            },
            hide: {
                hideAnnouncement(announcement)
            }
        )
    }
}

private struct CourseAnnouncementRow: View {
    private struct BrowserDestination: Identifiable {
        let id = UUID()
        let url: URL
    }

    let announcement: Announcement
    let isLoading: Bool
    let loadBody: () async -> Void
    let hide: () -> Void
    @State private var isExpanded = false
    @State private var browserDestination: BrowserDestination?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggleExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(announcement.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(
                        DisplayDateFormatter.dateTime.string(
                            from: announcement.publishedAt
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
                VStack(alignment: .leading, spacing: 8) {
                    if isLoading {
                        ProgressView("本文を読み込み中")
                    } else if announcement.displayBody.isEmpty {
                        Text("本文を取得できませんでした。")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(announcement.displayBody)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }

                    let links = announcement.bodyLinks
                    if !links.isEmpty {
                        Divider()
                        ForEach(links, id: \.self) { url in
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

            HStack(spacing: 14) {
                Button(action: toggleExpanded) {
                    DeadlineActionLabel(
                        title: isExpanded ? "閉じる" : "本文を表示",
                        systemImage: isExpanded
                            ? "chevron.up"
                            : "chevron.down"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    browserDestination = BrowserDestination(
                        url: announcement.tactURL
                    )
                } label: {
                    DeadlineActionLabel(
                        title: "TACTで開く",
                        systemImage: "safari"
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(action: hide) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                        .padding(7)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(announcement.title)を非表示")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: isExpanded) { _, expanded in
            guard expanded, announcement.body.isEmpty else { return }
            Task { await loadBody() }
        }
        .sheet(item: $browserDestination) { destination in
            NavigationStack {
                TactWebDestination(
                    url: destination.url,
                    title: destination.url == announcement.tactURL
                        ? announcement.title
                        : destination.url.host ?? "リンク"
                )
            }
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

    private func linkTitle(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host
        }
        return url.absoluteString
    }
}

private struct MaterialDisclosureRow: View {
    let material: CourseMaterial
    var depth = 0
    @State private var isExpanded = false

    @ViewBuilder
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if material.kind == .folder {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Label(
                            material.title,
                            systemImage: material.kind.systemImage
                        )
                        .lineLimit(2)

                        Spacer()

                        Text("\(material.children.count)件")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Image(
                            systemName: isExpanded
                                ? "chevron.up"
                                : "chevron.down"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        if material.children.isEmpty {
                            Text("このフォルダは空か、内容を取得できませんでした")
                                .foregroundStyle(.secondary)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                        } else {
                            ForEach(
                                Array(material.children.enumerated()),
                                id: \.element.id
                            ) { index, child in
                                MaterialDisclosureRow(
                                    material: child,
                                    depth: depth + 1
                                )

                                if index < material.children.count - 1 {
                                    Divider()
                                        .padding(
                                            .leading,
                                            CGFloat(depth + 1) * 12
                                        )
                                }
                            }
                        }
                    }
                    .transition(.opacity)
                }
            } else {
                NavigationLink {
                    TactWebDestination(
                        url: material.url,
                        title: material.title
                    )
                } label: {
                    Label(material.title, systemImage: material.kind.systemImage)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .padding(.leading, CGFloat(depth) * 12)
    }
}
