import Foundation

actor TactSessionService {
    enum ResponseFormat: Equatable {
        case json
        case html
        case any
    }

    enum SessionError: LocalizedError {
        case invalidURL
        case unauthenticated
        case unexpectedResponse
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "TACTのURLを作成できませんでした。"
            case .unauthenticated:
                return "TACTへのログインが必要です。"
            case .unexpectedResponse:
                return "TACTから不正な応答を受信しました。"
            case let .httpError(statusCode):
                return "TACTとの通信に失敗しました（HTTP \(statusCode)）。"
            }
        }
    }

    private let baseURL: URL
    private let urlSession: URLSession
    private var responseCache: [URL: Data] = [:]
    private var inFlightRequests: [URL: Task<Data, Error>] = [:]

    init(
        baseURL: URL = URL(string: "https://tact.ac.thers.ac.jp")!,
        configuration: URLSessionConfiguration = .default
    ) {
        self.baseURL = baseURL
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = .shared
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        self.urlSession = URLSession(configuration: configuration)
    }

    func install(cookies: [HTTPCookie]) {
        cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
        responseCache.removeAll()
        inFlightRequests.removeAll()
    }

    func clearCache() {
        responseCache.removeAll()
        inFlightRequests.removeAll()
    }

    func resetSession() {
        responseCache.removeAll()
        inFlightRequests.values.forEach { $0.cancel() }
        inFlightRequests.removeAll()
        HTTPCookieStorage.shared.cookies?
            .filter { $0.domain.contains("tact.ac.thers.ac.jp") }
            .forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        urlSession.configuration.urlCache?.removeAllCachedResponses()
        URLCache.shared.removeAllCachedResponses()
    }

    func get(
        path: String,
        queryItems: [URLQueryItem] = [],
        expectedFormat: ResponseFormat = .json,
        useCache: Bool = false
    ) async throws -> Data {
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SessionError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw SessionError.invalidURL
        }

        return try await get(
            url: url,
            expectedFormat: expectedFormat,
            useCache: useCache
        )
    }

    func get(
        url: URL,
        expectedFormat: ResponseFormat = .html,
        useCache: Bool = false
    ) async throws -> Data {
        if useCache, let cachedData = responseCache[url] {
            return cachedData
        }

        if useCache, let request = inFlightRequests[url] {
            return try await request.value
        }

        if useCache {
            let request = Task {
                try await Self.performGet(
                    urlSession: urlSession,
                    url: url,
                    expectedFormat: expectedFormat
                )
            }
            inFlightRequests[url] = request
            defer { inFlightRequests[url] = nil }
            let data = try await request.value
            responseCache[url] = data
            return data
        }

        return try await Self.performGet(
            urlSession: urlSession,
            url: url,
            expectedFormat: expectedFormat
        )
    }

    private static func performGet(
        urlSession: URLSession,
        url: URL,
        expectedFormat: ResponseFormat
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        switch expectedFormat {
        case .json:
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        case .html:
            request.setValue("text/html", forHTTPHeaderField: "Accept")
        case .any:
            request.setValue("*/*", forHTTPHeaderField: "Accept")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SessionError.unexpectedResponse
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw SessionError.unauthenticated
        }
        guard 200..<300 ~= response.statusCode else {
            throw SessionError.httpError(response.statusCode)
        }

        let contentType = response.value(forHTTPHeaderField: "Content-Type")?
            .lowercased() ?? ""
        let finalPath = response.url?.path.lowercased() ?? ""
        let reachedLogin = finalPath.contains("sakai-login-tool") ||
            finalPath.contains("shibboleth.sso")

        if reachedLogin {
            throw SessionError.unauthenticated
        }
        if expectedFormat == .json && !contentType.contains("json") {
            throw SessionError.unauthenticated
        }
        return data
    }

    func postForm(
        url: URL,
        fields: [String: String],
        expectedFormat: ResponseFormat = .html
    ) async throws -> Data {
        var components = URLComponents()
        components.queryItems = fields
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SessionError.unexpectedResponse
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw SessionError.unauthenticated
        }
        guard 200..<300 ~= response.statusCode else {
            throw SessionError.httpError(response.statusCode)
        }
        let finalPath = response.url?.path.lowercased() ?? ""
        if finalPath.contains("sakai-login-tool") ||
            finalPath.contains("shibboleth.sso") {
            throw SessionError.unauthenticated
        }
        return data
    }
}
