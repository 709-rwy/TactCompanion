import Foundation

struct TactPersistentCache: Codable {
    var seasonID: String
    var courses: [Course]?
    var assignments: [String: [Assignment]] = [:]
    var quizzes: [String: [Quiz]] = [:]
    var announcements: [String: [Announcement]] = [:]
}

enum TactPersistentCacheStore {
    static func load() -> TactPersistentCache {
        let currentSeason = seasonID()
        guard
            let data = try? Data(contentsOf: fileURL),
            let cache = try? JSONDecoder().decode(
                TactPersistentCache.self,
                from: data
            ),
            cache.seasonID == currentSeason
        else {
            clearSeasonData()
            return TactPersistentCache(seasonID: currentSeason)
        }
        return cache
    }

    static func save(_ cache: TactPersistentCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func clearAll() {
        clearSeasonData()
        UserDefaults.standard.removeObject(forKey: "selectedTimetableTerm")
    }

    static var currentSeasonID: String {
        seasonID()
    }

    private static func clearSeasonData() {
        remove()
        HiddenContentStore.clearAll()
        UserDefaults.standard.removeObject(
            forKey: "cachedTimetableActivityCounts"
        )
    }

    private static func seasonID(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        if (4...9).contains(month) {
            return "\(year)-spring"
        }
        return "\(month >= 10 ? year : year - 1)-autumn"
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appending(path: "TACTCompanion", directoryHint: .isDirectory)
    }

    private static var fileURL: URL {
        directoryURL.appending(path: "tact-cache.json")
    }
}
