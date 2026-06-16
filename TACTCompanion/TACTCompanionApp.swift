import SwiftUI

@main
@MainActor
struct TACTCompanionApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self)
    private var notificationDelegate
    private let repository: any TactRepositoryProtocol
    @StateObject private var settings = AppSettings()
    @StateObject private var refreshController = AppRefreshController()

    init() {
        let session = TactSessionService()
        repository = TactRepository(
            sessionService: session,
            assignmentService: TactAssignmentService(session: session),
            quizService: TactQuizService(session: session),
            announcementService: TactAnnouncementService(session: session),
            materialService: TactMaterialService(session: session)
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                viewModel: AuthenticationViewModel(
                    repository: repository
                ),
                repository: repository
            )
            .environmentObject(settings)
            .environmentObject(refreshController)
        }
    }
}
