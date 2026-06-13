import Foundation

protocol TactRepositoryProtocol: Sendable {
    func authenticate(cookies: [HTTPCookie]) async throws
    func fetchCourses() async throws -> [Course]
    func fetchAssignments(courseID: String) async throws -> [Assignment]
    func fetchQuizzes(courseID: String) async throws -> [Quiz]
    func fetchAnnouncements(courseID: String) async throws -> [Announcement]
    func fetchAnnouncementBody(
        courseID: String,
        announcementID: String,
        url: URL
    ) async throws -> String
    func fetchMaterials(courseID: String) async throws -> TactMaterialService.Result
    func invalidateCaches() async
    func invalidateCaches(courseID: String) async
    func logout() async
}

actor TactRepository: TactRepositoryProtocol {
    private static let quizCacheVersion = 2
    private static let quizCacheVersionKey = "tactQuizCacheVersion"

    private let sessionService: TactSessionService
    private let assignmentService: TactAssignmentService
    private let quizService: TactQuizService
    private let announcementService: TactAnnouncementService
    private let materialService: TactMaterialService
    private var coursesCache: [Course]?
    private var assignmentCache: [String: [Assignment]] = [:]
    private var quizCache: [String: [Quiz]] = [:]
    private var announcementCache: [String: [Announcement]] = [:]
    private var materialCache: [String: TactMaterialService.Result] = [:]
    private var assignmentRequests: [String: Task<[Assignment], Error>] = [:]
    private var quizRequests: [String: Task<[Quiz], Error>] = [:]
    private var announcementRequests: [String: Task<[Announcement], Error>] = [:]
    private var materialRequests:
        [String: Task<TactMaterialService.Result, Error>] = [:]
    private var persistentCache: TactPersistentCache

    init(
        sessionService: TactSessionService,
        assignmentService: TactAssignmentService,
        quizService: TactQuizService,
        announcementService: TactAnnouncementService,
        materialService: TactMaterialService
    ) {
        self.sessionService = sessionService
        self.assignmentService = assignmentService
        self.quizService = quizService
        self.announcementService = announcementService
        self.materialService = materialService
        let cache = TactPersistentCacheStore.load()
        self.persistentCache = cache
        self.coursesCache = cache.courses
        self.assignmentCache = cache.assignments
        self.quizCache = cache.quizzes
        self.announcementCache = cache.announcements

        let defaults = UserDefaults.standard
        if defaults.integer(forKey: Self.quizCacheVersionKey) <
            Self.quizCacheVersion {
            self.quizCache.removeAll()
            self.persistentCache.quizzes.removeAll()
            TactPersistentCacheStore.save(self.persistentCache)
            defaults.set(
                Self.quizCacheVersion,
                forKey: Self.quizCacheVersionKey
            )
        }
    }

    func authenticate(cookies: [HTTPCookie]) async throws {
        await sessionService.install(cookies: cookies)
        coursesCache = nil
        _ = try await fetchCourses()
    }

    func invalidateCaches() async {
        await sessionService.clearCache()
        clearRepositoryCaches()
        persistentCache = TactPersistentCache(
            seasonID: TactPersistentCacheStore.load().seasonID
        )
        TactPersistentCacheStore.remove()
    }

    func invalidateCaches(courseID: String) async {
        await sessionService.clearCache()
        assignmentCache[courseID] = nil
        quizCache[courseID] = nil
        announcementCache[courseID] = nil
        materialCache[courseID] = nil
        assignmentRequests[courseID]?.cancel()
        quizRequests[courseID]?.cancel()
        announcementRequests[courseID]?.cancel()
        materialRequests[courseID]?.cancel()
        assignmentRequests[courseID] = nil
        quizRequests[courseID] = nil
        announcementRequests[courseID] = nil
        materialRequests[courseID] = nil
        persistentCache.assignments[courseID] = nil
        persistentCache.quizzes[courseID] = nil
        persistentCache.announcements[courseID] = nil
        savePersistentCache()
    }

    func logout() async {
        await sessionService.resetSession()
        clearRepositoryCaches()
        persistentCache = TactPersistentCache(
            seasonID: TactPersistentCacheStore.currentSeasonID
        )
        TactPersistentCacheStore.clearAll()
        WidgetSnapshotStore.clear()
    }

    private func clearRepositoryCaches() {
        coursesCache = nil
        assignmentCache.removeAll()
        quizCache.removeAll()
        announcementCache.removeAll()
        materialCache.removeAll()
        assignmentRequests.values.forEach { $0.cancel() }
        quizRequests.values.forEach { $0.cancel() }
        announcementRequests.values.forEach { $0.cancel() }
        materialRequests.values.forEach { $0.cancel() }
        assignmentRequests.removeAll()
        quizRequests.removeAll()
        announcementRequests.removeAll()
        materialRequests.removeAll()
    }

    func fetchCourses() async throws -> [Course] {
        if let coursesCache {
            return coursesCache
        }
        let data = try await sessionService.get(
            path: "/portal",
            expectedFormat: .html,
            useCache: true
        )
        guard let html = String(data: data, encoding: .utf8) else {
            throw TactSessionService.SessionError.unexpectedResponse
        }
        let courses = TactHTMLParser.courses(from: html)
        guard !courses.isEmpty else {
            throw TactSessionService.SessionError.unauthenticated
        }
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: .now)
        let month = calendar.component(.month, from: .now)
        let academicYear = month >= 4 ? year : year - 1
        let currentCourses = courses.filter { $0.academicYear == academicYear }
        coursesCache = currentCourses
        persistentCache.courses = currentCourses
        savePersistentCache()
        return currentCourses
    }

    func fetchAssignments(courseID: String) async throws -> [Assignment] {
        if let cached = assignmentCache[courseID] {
            return cached
        }
        if let request = assignmentRequests[courseID] {
            return try await request.value
        }
        let service = assignmentService
        let request = Task {
            try await service.fetchAssignments(siteID: courseID)
        }
        assignmentRequests[courseID] = request
        defer { assignmentRequests[courseID] = nil }
        let values = try await request.value
        assignmentCache[courseID] = values
        persistentCache.assignments[courseID] = values
        savePersistentCache()
        return values
    }

    func fetchQuizzes(courseID: String) async throws -> [Quiz] {
        if let cached = quizCache[courseID] {
            return cached
        }
        if let request = quizRequests[courseID] {
            return try await request.value
        }
        let service = quizService
        let request = Task {
            try await service.fetchQuizzes(siteID: courseID)
        }
        quizRequests[courseID] = request
        defer { quizRequests[courseID] = nil }
        let values = try await request.value
        quizCache[courseID] = values
        persistentCache.quizzes[courseID] = values
        savePersistentCache()
        return values
    }

    func fetchAnnouncements(courseID: String) async throws -> [Announcement] {
        if let cached = announcementCache[courseID] {
            return cached
        }
        if let request = announcementRequests[courseID] {
            return try await request.value
        }
        let service = announcementService
        let request = Task {
            try await service.fetchAnnouncements(siteID: courseID)
        }
        announcementRequests[courseID] = request
        defer { announcementRequests[courseID] = nil }
        let values = try await request.value
        announcementCache[courseID] = values
        persistentCache.announcements[courseID] = values
        savePersistentCache()
        return values
    }

    func fetchAnnouncementBody(
        courseID: String,
        announcementID: String,
        url: URL
    ) async throws -> String {
        if
            let announcement = announcementCache[courseID]?
                .first(where: { $0.id == announcementID }),
            !announcement.body.isEmpty
        {
            return announcement.body
        }

        let body = try await announcementService.fetchBody(url: url)
        guard
            var announcements = announcementCache[courseID],
            let index = announcements.firstIndex(where: {
                $0.id == announcementID
            })
        else {
            return body
        }
        let old = announcements[index]
        announcements[index] = Announcement(
            id: old.id,
            courseID: old.courseID,
            title: old.title,
            body: body,
            publishedAt: old.publishedAt,
            tactURL: old.tactURL
        )
        announcementCache[courseID] = announcements
        persistentCache.announcements[courseID] = announcements
        savePersistentCache()
        return body
    }

    func fetchMaterials(courseID: String) async throws -> TactMaterialService.Result {
        if let cached = materialCache[courseID] {
            return cached
        }
        if let request = materialRequests[courseID] {
            return try await request.value
        }
        let service = materialService
        let request = Task {
            try await service.fetchMaterials(siteID: courseID)
        }
        materialRequests[courseID] = request
        defer { materialRequests[courseID] = nil }
        let result = try await request.value
        materialCache[courseID] = result
        return result
    }

    private func savePersistentCache() {
        TactPersistentCacheStore.save(persistentCache)
    }
}
