import Combine
import Foundation
import WebKit

@MainActor
final class AuthenticationViewModel: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isChecking = false
    @Published private(set) var hasCompletedInitialCheck = false
    @Published var errorMessage: String?

    private let repository: any TactRepositoryProtocol

    init(repository: any TactRepositoryProtocol) {
        self.repository = repository
    }

    func checkExistingSession() async {
        guard !hasCompletedInitialCheck else { return }
        guard !isChecking else { return }
        isChecking = true
        defer {
            isChecking = false
            hasCompletedInitialCheck = true
        }

        do {
            let webCookies = await storedTACTCookies()
            let cookies = mergedCookies(webCookies + TactCookieStore.load())
            if !cookies.isEmpty {
                await installInWebView(cookies)
                try await repository.authenticate(cookies: cookies)
            } else {
                _ = try await repository.fetchCourses()
            }
            isAuthenticated = true
            errorMessage = nil
        } catch {
            isAuthenticated = false
            errorMessage = nil
        }
    }

    func completeWebLogin(cookies: [HTTPCookie]) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            await repository.invalidateCaches()
            try await repository.authenticate(cookies: cookies)
            TactCookieStore.save(cookies)
            isAuthenticated = true
            errorMessage = nil
        } catch {
            isAuthenticated = false
            errorMessage = nil
        }
    }

    func logout() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        await repository.logout()
        TactCookieStore.clear()
        await clearWebSession()
        isAuthenticated = false
        hasCompletedInitialCheck = true
        errorMessage = nil
    }

    private func storedTACTCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                continuation.resume(
                    returning: $0.filter {
                        $0.domain.contains("tact.ac.thers.ac.jp")
                    }
                )
            }
        }
    }

    private func installInWebView(_ cookies: [HTTPCookie]) async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in cookies {
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    private func clearWebSession() async {
        let dataStore = WKWebsiteDataStore.default()
        let cookies = await storedTACTCookies()
        for cookie in cookies {
            await withCheckedContinuation { continuation in
                dataStore.httpCookieStore.delete(cookie) {
                    continuation.resume()
                }
            }
        }

        let records = await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()
            ) {
                continuation.resume(returning: $0)
            }
        }
        let tactRecords = records.filter {
            $0.displayName.contains("tact.ac.thers.ac.jp") ||
            $0.displayName.contains("thers.ac.jp")
        }
        guard !tactRecords.isEmpty else { return }
        await withCheckedContinuation { continuation in
            dataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                for: tactRecords
            ) {
                continuation.resume()
            }
        }
    }

    private func mergedCookies(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
        var values: [String: HTTPCookie] = [:]
        for cookie in cookies {
            let key = "\(cookie.domain)|\(cookie.path)|\(cookie.name)"
            values[key] = cookie
        }
        return Array(values.values)
    }
}
