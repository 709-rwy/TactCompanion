import SwiftUI

struct RootView: View {
    @StateObject private var viewModel: AuthenticationViewModel
    private let repository: any TactRepositoryProtocol

    init(
        viewModel: AuthenticationViewModel,
        repository: any TactRepositoryProtocol
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.repository = repository
    }

    var body: some View {
        Group {
            if viewModel.isAuthenticated {
                MainTabView(
                    repository: repository,
                    authenticationViewModel: viewModel
                )
            } else if !viewModel.hasCompletedInitialCheck {
                ProgressView("ログイン状態を確認中")
            } else {
                LoginView(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.checkExistingSession()
        }
    }
}
