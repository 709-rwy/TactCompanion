import Combine
import Foundation

@MainActor
final class AppRefreshController: ObservableObject {
    @Published private(set) var requestID = UUID()

    func requestRefresh() {
        requestID = UUID()
    }
}
