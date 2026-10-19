import Foundation

nonisolated enum L10n {
    static func string(_ key: String) -> String { key }
    static func format(_ key: String, _ values: CVarArg...) -> String { key }
    static func joined(_ values: [String], separatorKey: String) -> String { values.joined(separator: "/") }
}
nonisolated struct PodcastPlaybackMetadata: Codable, Hashable {}
struct Podcast: Identifiable { let id: Int; var isSubscribed = true }
struct PodcastPage { let podcasts: [Podcast]; let totalCount: Int?; let hasMore: Bool }
enum APIError: Error { case notLoggedIn; case offline }
enum ContentFeature { case podcasts, listeningHistory }
final class AppSettings {
    var cookie = "test-account-a"
    func isContentFeatureEnabled(_ feature: ContentFeature) -> Bool { true }
    func clearAccount() { cookie = "" }
}

final class NeteaseAPI {
    var events: [String] = []
    var userID = 1
    var failProfile = false
    var holdProfileOnce = false
    var heldProfile: CheckedContinuation<AccountProfile, Error>?
    var holdSupplements = false
    var heldSupplements: [String: CheckedContinuation<Void, Never>] = [:]
    var ids = Array(1...350)

    func accountProfile() async throws -> AccountProfile {
        events.append("account")
        let profile = try JSONDecoder().decode(AccountProfile.self, from: Data("{\"userId\":\(userID),\"nickname\":\"Tester\"}".utf8))
        if failProfile { throw APIError.offline }
        if holdProfileOnce {
            holdProfileOnce = false
            return try await withCheckedThrowingContinuation { heldProfile = $0 }
        }
        return profile
    }
    func userPlaylists(userID: Int) async throws -> [Playlist] {
        events.append("playlists")
        return [Playlist(id: 99, name: "Favorites")]
    }
    func likedSongIDs(userID: Int, likedPlaylistID: Int?) async throws -> [Int] {
        events.append("ids")
        return ids
    }
    func songDetailsPage(ids: [Int], offset: Int, limit: Int) async throws -> SongCollectionPage {
        events.append("songs")
        let end = min(offset + limit, ids.count)
        return SongCollectionPage(songs: ids[offset..<end].map(Self.song), nextOffset: end, totalCount: ids.count)
    }
    static func song(_ id: Int) -> Song { Song(id: id, name: "Song \(id)", artists: [], durationMS: 240_000) }
    private func supplement(_ name: String) async {
        events.append(name)
        if holdSupplements { await withCheckedContinuation { heldSupplements[name] = $0 } }
    }
    func releaseSupplements() {
        holdSupplements = false
        let continuations = heldSupplements.values
        heldSupplements = [:]
        for continuation in continuations { continuation.resume() }
    }
    func userDetail(userID: Int) async throws -> AccountDetail {
        await supplement("detail")
        let profile = try JSONDecoder().decode(AccountProfile.self, from: Data("{\"userId\":\(userID),\"nickname\":\"Tester\"}".utf8))
        return AccountDetail(profile: profile, level: 1, listenSongs: 1, createDays: 1)
    }
    func subscribedAlbums() async throws -> [Album] { await supplement("albums"); return [] }
    func subscribedArtists() async throws -> [Artist] { await supplement("artists"); return [] }
    func subscribedPodcasts(offset: Int = 0, limit: Int) async throws -> PodcastPage {
        await supplement("podcasts")
        return PodcastPage(podcasts: [], totalCount: 0, hasMore: false)
    }
    func recentSongs() async throws -> [Song] { await supplement("history"); return [] }
    func setArtistFollowed(id: Int, isFollowed: Bool) async throws {}
    func setAlbumSubscribed(id: Int, isSubscribed: Bool) async throws {}
    func setSongLiked(id: Int, isLiked: Bool) async throws {}
    func setPlaylistSubscribed(id: Int, isSubscribed: Bool) async throws {}
    func setPodcastSubscribed(id: Int, isSubscribed: Bool) async throws {}
    func deletePlaylist(id: Int) async throws {}
    func createPlaylist(name: String, isPrivate: Bool) async throws -> Playlist { Playlist(id: 100, name: name) }
    func removeSong(id: Int, fromPlaylistID: Int) async throws {}
    func addSong(id: Int, toPlaylistID: Int) async throws {}
}

enum Failure: Error { case check(String) }
@main struct Checks {
    static func expect(_ condition: @autoclosure () -> Bool, _ description: String) throws {
        guard condition() else { throw Failure.check(description) }
    }
    static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        throw Failure.check("Async condition did not finish")
    }
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "Music-Library-Data-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FavoriteLibraryCache(directory: directory)
        let settings = AppSettings()
        let api = NeteaseAPI()
        let library = LibraryStore(api: api, settings: settings, favoriteCache: cache)

        api.holdSupplements = true
        let refresh = Task { await library.refresh() }
        try await until { api.heldSupplements.count == 5 }
        try expect(library.favoriteSongs.count == 100 && library.phase == .loaded,
                   "Favorites waited for unrelated account/library sections")
        try expect(Array(api.events.prefix(4)) == ["account", "playlists", "ids", "songs"],
                   "Favorites did not load before supplements")
        api.releaseSupplements()
        await refresh.value
        print("PASS favorites visible before five concurrent supplementary requests complete")

        let snapshot = cache.load(for: settings.cookie)!
        try expect(snapshot.songs.count == 100 && snapshot.songIDs.count == 350 && snapshot.nextOffset == 100,
                   "Cache did not bound detail count or retain ordered IDs")
        let coldAPI = NeteaseAPI()
        let cold = LibraryStore(api: coldAPI, settings: settings, favoriteCache: cache)
        try expect(cold.favoriteSongs.map(\.id) == Array(1...100) && coldAPI.events.isEmpty,
                   "Cold launch required network before restoring favorites")
        print("PASS cached first page restores synchronously with all ordered IDs and no network")

        coldAPI.failProfile = true
        await cold.refresh()
        try expect(cold.favoriteSongs.count == 100 && cold.profile?.id == 1, "Offline refresh erased cached rows")
        print("PASS offline refresh preserves visible cached favorites")

        let plan = library.favoritePlaybackPlan()
        try expect(plan.songs.count == 100 && plan.remainingSongIDs == Array(101...350), "Playback plan lost or duplicated IDs")
        try expect(!api.events.dropFirst(4).contains("songs"), "Playback plan performed a blocking metadata request")
        print("PASS Play All plan returns loaded songs and remaining IDs without network")

        let otherSettings = AppSettings()
        otherSettings.cookie = "test-account-b"
        let other = LibraryStore(api: NeteaseAPI(), settings: otherSettings, favoriteCache: cache)
        try expect(other.favoriteSongs.isEmpty && other.profile == nil, "Cache leaked across account sessions")
        cold.clearAccountData()
        try expect(cache.load(for: settings.cookie) == nil, "Logout did not clear current cache")
        print("PASS cache isolates accounts and clears on logout")

        cache.save(snapshot, for: settings.cookie)
        _ = cache.load(for: settings.cookie)
        let file = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first!
        try expect(!file.lastPathComponent.contains(settings.cookie), "Cache file name contains cookie")
        let json = try String(contentsOf: file, encoding: .utf8)
        try expect(!json.contains(settings.cookie), "Cache content contains cookie")
        try Data("invalid json".utf8).write(to: file)
        try expect(cache.load(for: settings.cookie) == nil, "Corrupt cache was accepted")
        print("PASS opaque cache keys, no stored cookie, and corrupt-cache fallback")

        let raceAPI = NeteaseAPI()
        raceAPI.holdProfileOnce = true
        let race = LibraryStore(api: raceAPI, settings: settings, favoriteCache: cache)
        let old = Task { await race.refresh() }
        try await until { raceAPI.heldProfile != nil }
        settings.cookie = "test-account-b"
        raceAPI.userID = 2
        await race.refresh()
        let oldProfile = try JSONDecoder().decode(AccountProfile.self, from: Data(#"{"userId":1,"nickname":"Old"}"#.utf8))
        raceAPI.heldProfile?.resume(returning: oldProfile)
        await old.value
        try expect(race.profile?.id == 2, "Old account request overwrote the new session")
        print("PASS late account response cannot overwrite a new session")

        let expansion = PlaybackQueueExpansion()
        var pages: [[Int]] = []
        var appended: [Int] = []
        expansion.start(ids: Array(101...350), load: { ids in
            pages.append(ids)
            return ids.reversed().map(NeteaseAPI.song)
        }, append: { appended.append(contentsOf: $0.map(\.id)) })
        while expansion.isLoading { await expansion.waitForNextPage() }
        try expect(pages.map(\.count) == [100, 100, 50] && appended == Array(101...350),
                   "Expansion failed to restore ordered batches")
        print("PASS queue expands in ordered batches without dropping IDs")

        var failOnce = true
        appended = []
        expansion.start(ids: [7, 8, 9], load: { ids in
            if failOnce { failOnce = false; throw APIError.offline }
            return ids.map(NeteaseAPI.song)
        }, append: { appended.append(contentsOf: $0.map(\.id)) })
        await expansion.waitForNextPage()
        try expect(expansion.failureMessage != nil && appended.isEmpty, "Failed page was silently discarded")
        expansion.retry()
        await expansion.waitForNextPage()
        try expect(appended == [7, 8, 9] && expansion.failureMessage == nil, "Retry lost or duplicated entries")
        print("PASS retry retains failed batch and appends it once")

        var held: CheckedContinuation<[Song], Never>?
        appended = []
        expansion.start(ids: [1], load: { _ in await withCheckedContinuation { held = $0 } },
                        append: { appended.append(contentsOf: $0.map(\.id)) })
        try await until { held != nil }
        expansion.start(ids: [2], load: { $0.map(NeteaseAPI.song) },
                        append: { appended.append(contentsOf: $0.map(\.id)) })
        held?.resume(returning: [NeteaseAPI.song(1)])
        await expansion.waitForNextPage()
        try await until { appended == [2] }
        try expect(appended == [2], "Superseded queue appended an old page")
        print("PASS superseded queue cannot append stale metadata")
        print("10 library/cache/queue checks passed")
    }
}
