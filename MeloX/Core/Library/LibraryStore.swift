import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    private(set) var profile: AccountProfile?
    private(set) var accountDetail: AccountDetail?
    private(set) var favoriteSongs: [Song] = []
    private(set) var favoritePlaylists: [Playlist] = []
    private(set) var favoriteAlbums: [Album] = []
    private(set) var favoriteArtists: [Artist] = []
    private(set) var subscribedPodcasts: [Podcast] = []
    private(set) var recentSongs: [Song] = []
    private(set) var likedPlaylistID: Int?
    private(set) var favoriteSongTotalCount = 0
    private(set) var favoriteSongsNextOffset = 0
    private(set) var isLoadingMoreFavoriteSongs = false
    private(set) var favoriteSongsLoadMoreError: String?
    private(set) var subscribedPodcastTotalCount = 0
    private(set) var subscribedPodcastsNextOffset = 0
    private(set) var hasMoreSubscribedPodcasts = false
    private(set) var isLoadingMoreSubscribedPodcasts = false
    private(set) var subscribedPodcastsLoadMoreError: String?
    private(set) var phase: LoadingPhase = .loaded
    private(set) var errorMessage: String?

    @ObservationIgnored
    private let api: NeteaseAPI

    @ObservationIgnored
    private let settings: AppSettings

    @ObservationIgnored private let favoriteCache: FavoriteLibraryCache
    @ObservationIgnored private var contentCookie: String?
    @ObservationIgnored private var activeRefreshID: UUID?

    @ObservationIgnored
    private var loadedCookie: String?

    @ObservationIgnored
    private var refreshingCookie: String?

    @ObservationIgnored
    private var favoriteSongIDs: [Int] = []

    @ObservationIgnored
    private var favoriteSongIDSet: Set<Int> = []

    @ObservationIgnored
    private let favoriteSongPageSize = 100

    @ObservationIgnored
    private var favoriteSongPageLoadTask: Task<Void, Never>?

    @ObservationIgnored
    private var favoriteSongPageLoadID: UUID?

    @ObservationIgnored
    private let subscribedPodcastPageSize = 50

    @ObservationIgnored
    private var subscribedPodcastPageLoadTask: Task<Void, Never>?

    @ObservationIgnored
    private var subscribedPodcastPageLoadID: UUID?

    init(api: NeteaseAPI, settings: AppSettings, favoriteCache: FavoriteLibraryCache? = nil) {
        self.api = api
        self.settings = settings
        self.favoriteCache = favoriteCache ?? FavoriteLibraryCache()
        restoreFavoriteCache(for: normalizedCookie)
    }

    private var normalizedCookie: String {
        settings.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restoreFavoriteCache(for cookie: String) {
        guard !cookie.isEmpty else { return }
        contentCookie = cookie
        guard let snapshot = favoriteCache.load(for: cookie) else { return }
        profile = snapshot.profile
        likedPlaylistID = snapshot.likedPlaylistID
        favoriteSongIDs = snapshot.songIDs
        favoriteSongIDSet = Set(snapshot.songIDs)
        favoriteSongTotalCount = snapshot.songIDs.count
        favoriteSongs = snapshot.songs
        favoriteSongsNextOffset = snapshot.nextOffset
    }

    private func persistFavoriteCache() {
        guard let profile, let cookie = contentCookie, cookie == normalizedCookie else { return }
        let offset = min(favoriteSongsNextOffset, favoriteSongPageSize)
        let firstIDs = Array(favoriteSongIDs.prefix(offset))
        let byID = Dictionary(favoriteSongs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        favoriteCache.save(FavoriteLibrarySnapshot(
            version: 1, profile: profile, likedPlaylistID: likedPlaylistID,
            songIDs: favoriteSongIDs, songs: firstIDs.compactMap { byID[$0] }, nextOffset: offset
        ), for: cookie)
    }

    private func isCurrentRefresh(_ id: UUID, cookie: String) -> Bool {
        !Task.isCancelled && activeRefreshID == id && normalizedCookie == cookie
    }

    var isLoggedIn: Bool {
        !settings.cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var ownedPlaylists: [Playlist] {
        guard let userID = profile?.id else { return [] }
        return favoritePlaylists.filter { $0.creator?.userID == userID }
    }

    var hasMoreFavoriteSongs: Bool {
        favoriteSongsNextOffset < favoriteSongTotalCount
    }

    var canStartHeartMode: Bool {
        likedPlaylistID != nil && favoriteSongTotalCount > 0
    }

    func randomHeartModeSeedSongID() -> Int? {
        favoriteSongIDs.randomElement()
    }

    func contains(song: Song) -> Bool {
        favoriteSongIDSet.contains(song.id)
    }

    func contains(playlist: Playlist) -> Bool {
        favoritePlaylists.contains { $0.id == playlist.id }
    }

    func contains(artist: Artist) -> Bool {
        favoriteArtists.contains { $0.id == artist.id }
    }

    func contains(album: Album) -> Bool {
        favoriteAlbums.contains { $0.id == album.id }
    }

    func setArtistFollowed(_ artist: Artist, isFollowed: Bool) async throws {
        guard isLoggedIn else { throw APIError.notLoggedIn }
        try await api.setArtistFollowed(id: artist.id, isFollowed: isFollowed)
        favoriteArtists.removeAll { $0.id == artist.id }
        if isFollowed {
            favoriteArtists.insert(artist, at: 0)
        }
    }

    func setAlbumSubscribed(
        _ album: Album,
        isSubscribed: Bool
    ) async throws {
        guard isLoggedIn else { throw APIError.notLoggedIn }
        try await api.setAlbumSubscribed(id: album.id, isSubscribed: isSubscribed)
        favoriteAlbums.removeAll { $0.id == album.id }
        if isSubscribed {
            favoriteAlbums.insert(album, at: 0)
        }
    }

    func contains(podcast: Podcast) -> Bool {
        subscribedPodcasts.contains { $0.id == podcast.id }
    }

    func recordRecentlyPlayed(_ song: Song) {
        guard settings.isContentFeatureEnabled(.listeningHistory) else {
            return
        }
        recentSongs.removeAll { $0.id == song.id }
        recentSongs.insert(song, at: 0)
        if recentSongs.count > 100 {
            recentSongs.removeLast(recentSongs.count - 100)
        }
    }

    func canUnsubscribe(_ playlist: Playlist) -> Bool {
        playlist.creator?.userID != profile?.id
    }

    func refresh(force: Bool = false) async {
        let cookie = normalizedCookie
        guard !cookie.isEmpty else {
            clearAccountData()
            return
        }
        guard refreshingCookie != cookie else { return }
        guard force || loadedCookie != cookie || phase != .loaded else { return }

        if contentCookie != cookie {
            clearRemoteContent()
            restoreFavoriteCache(for: cookie)
        }
        let refreshID = UUID()
        activeRefreshID = refreshID
        refreshingCookie = cookie
        defer {
            if activeRefreshID == refreshID {
                refreshingCookie = nil
                activeRefreshID = nil
            }
        }
        phase = .loading
        errorMessage = nil
        favoriteSongsLoadMoreError = nil
        subscribedPodcastsLoadMoreError = nil

        do {
            let loadedProfile = try await api.accountProfile()
            guard isCurrentRefresh(refreshID, cookie: cookie) else { return }
            profile = loadedProfile
            loadedCookie = cookie
            var partialFailures: [String] = []

            // Only the identity and liked-playlist requests precede favorites.
            // Optional account/library sections load after the first song page.
            do {
                let playlists = try await api.userPlaylists(userID: loadedProfile.id)
                guard isCurrentRefresh(refreshID, cookie: cookie) else { return }
                likedPlaylistID = playlists.first?.id
                favoritePlaylists = Array(playlists.dropFirst())
            } catch {
                guard isCurrentRefresh(refreshID, cookie: cookie) else { return }
                partialFailures.append(L10n.format("ui.library.error.playlists", error.localizedDescription))
            }

            do {
                let ids = try await api.likedSongIDs(userID: loadedProfile.id, likedPlaylistID: likedPlaylistID)
                guard isCurrentRefresh(refreshID, cookie: cookie) else { return }
                var seen = Set<Int>()
                let orderedIDs = ids.filter { $0 > 0 && seen.insert($0).inserted }
                let firstPage = try await api.songDetailsPage(ids: orderedIDs, offset: 0, limit: favoriteSongPageSize)
                guard isCurrentRefresh(refreshID, cookie: cookie) else { return }
                favoriteSongIDs = orderedIDs
                favoriteSongIDSet = Set(orderedIDs)
                favoriteSongTotalCount = orderedIDs.count
                favoriteSongs = firstPage.songs
                favoriteSongsNextOffset = firstPage.nextOffset
                favoriteSongsLoadMoreError = nil
                persistFavoriteCache()
            } catch {
                guard isCurrentRefresh(refreshID, cookie: cookie) else { return }
                partialFailures.append(L10n.format("ui.library.error.favorite_songs", error.localizedDescription))
            }
            async let detail: String? = loadAdditionalResource(
                cookie: cookie, refreshID: refreshID, failureKey: nil,
                load: { try await self.api.userDetail(userID: loadedProfile.id) },
                apply: { self.accountDetail = $0; self.profile = $0.profile }
            )
            async let albums: String? = loadAdditionalResource(
                cookie: cookie, refreshID: refreshID, failureKey: "ui.library.error.favorite_albums",
                load: { try await self.api.subscribedAlbums() },
                apply: { self.favoriteAlbums = $0 }
            )
            async let artists: String? = loadAdditionalResource(
                cookie: cookie, refreshID: refreshID, failureKey: "ui.library.error.favorite_artists",
                load: { try await self.api.subscribedArtists() },
                apply: { self.favoriteArtists = $0 }
            )
            async let podcasts: String? = refreshSubscribedPodcasts(cookie: cookie, refreshID: refreshID)
            async let history: String? = refreshHistory(cookie: cookie, refreshID: refreshID)
            let results = await (detail, albums, artists, podcasts, history)
            guard isCurrentRefresh(refreshID, cookie: cookie) else { return }
            partialFailures.append(contentsOf: [results.0, results.1, results.2, results.3, results.4].compactMap { $0 })
            if !partialFailures.isEmpty {
                errorMessage = L10n.format("ui.library.error.partial", partialFailures.joined(separator: "\n"))
            }
            phase = .loaded
        } catch {
            guard isCurrentRefresh(refreshID, cookie: cookie) else { return }
            if case APIError.notLoggedIn = error {
                settings.clearAccount()
                clearAccountData()
            } else if profile == nil {
                phase = .failed(error.localizedDescription)
            } else {
                phase = .loaded
                errorMessage = L10n.format("ui.library.error.account_refresh", error.localizedDescription)
            }
        }
    }

    private func loadAdditionalResource<Value>(
        cookie: String,
        refreshID: UUID,
        failureKey: String?,
        load: @MainActor () async throws -> Value,
        apply: @MainActor (Value) -> Void
    ) async -> String? {
        do {
            let value = try await load()
            guard isCurrentRefresh(refreshID, cookie: cookie) else { return nil }
            apply(value)
        } catch {
            guard isCurrentRefresh(refreshID, cookie: cookie), let failureKey else { return nil }
            return L10n.format(failureKey, error.localizedDescription)
        }
        return nil
    }

    private func refreshSubscribedPodcasts(cookie: String, refreshID: UUID) async -> String? {
        guard settings.isContentFeatureEnabled(.podcasts) else { return nil }
        return await loadAdditionalResource(
            cookie: cookie, refreshID: refreshID, failureKey: "ui.library.error.subscribed_podcasts",
            load: { try await self.api.subscribedPodcasts(limit: self.subscribedPodcastPageSize) },
            apply: { page in
                self.subscribedPodcasts = self.normalizedSubscribedPodcasts(page.podcasts)
                self.subscribedPodcastTotalCount = max(page.totalCount ?? self.subscribedPodcasts.count, self.subscribedPodcasts.count)
                self.subscribedPodcastsNextOffset = page.podcasts.count
                self.hasMoreSubscribedPodcasts = page.hasMore
                self.subscribedPodcastsLoadMoreError = nil
            }
        )
    }

    private func refreshHistory(cookie: String, refreshID: UUID) async -> String? {
        guard settings.isContentFeatureEnabled(.listeningHistory) else { return nil }
        return await loadAdditionalResource(
            cookie: cookie, refreshID: refreshID, failureKey: "ui.library.error.history",
            load: { try await self.api.recentSongs() },
            apply: { self.recentSongs = $0 }
        )
    }

    func loadMoreFavoriteSongs() async {
        if let favoriteSongPageLoadTask {
            await favoriteSongPageLoadTask.value
            return
        }

        guard hasMoreFavoriteSongs else { return }

        let requestedOffset = favoriteSongsNextOffset
        let requestedIDs = favoriteSongIDs
        let loadID = UUID()
        let loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadFavoriteSongsPage(
                ids: requestedIDs,
                offset: requestedOffset
            )
        }
        favoriteSongPageLoadID = loadID
        favoriteSongPageLoadTask = loadTask

        await loadTask.value

        guard favoriteSongPageLoadID == loadID else { return }
        favoriteSongPageLoadTask = nil
        favoriteSongPageLoadID = nil
    }

    func loadRemainingFavoriteSongs() async {
        while hasMoreFavoriteSongs {
            guard !Task.isCancelled else { return }
            let previousOffset = favoriteSongsNextOffset
            await loadMoreFavoriteSongs()
            guard favoriteSongsNextOffset > previousOffset else { return }
        }
    }

    func favoritePlaybackPlan() -> FavoritePlaybackPlan {
        FavoritePlaybackPlan(
            songs: favoriteSongs,
            remainingSongIDs: Array(favoriteSongIDs.dropFirst(favoriteSongsNextOffset)),
            accountCookie: normalizedCookie
        )
    }

    private func loadFavoriteSongsPage(
        ids requestedIDs: [Int],
        offset requestedOffset: Int
    ) async {
        isLoadingMoreFavoriteSongs = true
        favoriteSongsLoadMoreError = nil
        defer { isLoadingMoreFavoriteSongs = false }

        do {
            let page = try await api.songDetailsPage(
                ids: requestedIDs,
                offset: requestedOffset,
                limit: favoriteSongPageSize
            )
            try Task.checkCancellation()
            guard favoriteSongIDs == requestedIDs,
                  favoriteSongsNextOffset == requestedOffset else {
                return
            }

            var loadedIDs = Set(favoriteSongs.map(\.id))
            favoriteSongs.append(
                contentsOf: page.songs.filter {
                    loadedIDs.insert($0.id).inserted
                }
            )
            favoriteSongsNextOffset = page.nextOffset
        } catch is CancellationError {
            return
        } catch {
            favoriteSongsLoadMoreError = error.localizedDescription
        }
    }

    func loadMoreSubscribedPodcasts() async {
        guard settings.isContentFeatureEnabled(.podcasts) else { return }
        if let subscribedPodcastPageLoadTask {
            await subscribedPodcastPageLoadTask.value
            return
        }

        guard hasMoreSubscribedPodcasts else { return }

        let requestedOffset = subscribedPodcastsNextOffset
        let loadID = UUID()
        let loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadSubscribedPodcastPage(
                offset: requestedOffset
            )
        }
        subscribedPodcastPageLoadID = loadID
        subscribedPodcastPageLoadTask = loadTask

        await loadTask.value

        guard subscribedPodcastPageLoadID == loadID else { return }
        subscribedPodcastPageLoadTask = nil
        subscribedPodcastPageLoadID = nil
    }

    func loadRemainingSubscribedPodcasts() async {
        while hasMoreSubscribedPodcasts {
            guard !Task.isCancelled else { return }
            let previousOffset = subscribedPodcastsNextOffset
            await loadMoreSubscribedPodcasts()
            guard subscribedPodcastsNextOffset > previousOffset else {
                return
            }
        }
    }

    private func loadSubscribedPodcastPage(
        offset requestedOffset: Int
    ) async {
        isLoadingMoreSubscribedPodcasts = true
        subscribedPodcastsLoadMoreError = nil
        defer { isLoadingMoreSubscribedPodcasts = false }

        do {
            let page = try await api.subscribedPodcasts(
                offset: requestedOffset,
                limit: subscribedPodcastPageSize
            )
            try Task.checkCancellation()
            guard subscribedPodcastsNextOffset == requestedOffset else {
                return
            }

            var loadedIDs = Set(subscribedPodcasts.map(\.id))
            subscribedPodcasts.append(
                contentsOf: normalizedSubscribedPodcasts(
                    page.podcasts
                ).filter {
                    loadedIDs.insert($0.id).inserted
                }
            )
            subscribedPodcastsNextOffset =
                requestedOffset + page.podcasts.count
            subscribedPodcastTotalCount = max(
                page.totalCount ?? subscribedPodcastTotalCount,
                subscribedPodcasts.count
            )
            hasMoreSubscribedPodcasts =
                page.hasMore && !page.podcasts.isEmpty
        } catch is CancellationError {
            return
        } catch {
            subscribedPodcastsLoadMoreError =
                error.localizedDescription
        }
    }

    func toggle(song: Song) {
        guard isLoggedIn else {
            errorMessage = APIError.notLoggedIn.localizedDescription
            return
        }

        let wasLiked = contains(song: song)
        setLocalSong(song, isLiked: !wasLiked)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.api.setSongLiked(id: song.id, isLiked: !wasLiked)
            } catch {
                self.setLocalSong(song, isLiked: wasLiked)
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func toggle(playlist: Playlist) {
        guard isLoggedIn else {
            errorMessage = APIError.notLoggedIn.localizedDescription
            return
        }

        let wasSubscribed = contains(playlist: playlist)
        guard !wasSubscribed || canUnsubscribe(playlist) else { return }
        if wasSubscribed {
            favoritePlaylists.removeAll { $0.id == playlist.id }
        } else {
            var summary = playlist
            summary.tracks = []
            favoritePlaylists.insert(summary, at: 0)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.api.setPlaylistSubscribed(
                    id: playlist.id,
                    isSubscribed: !wasSubscribed
                )
            } catch {
                if wasSubscribed {
                    self.favoritePlaylists.insert(playlist, at: 0)
                } else {
                    self.favoritePlaylists.removeAll { $0.id == playlist.id }
                }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func toggle(podcast: Podcast) {
        guard isLoggedIn else {
            errorMessage = APIError.notLoggedIn.localizedDescription
            return
        }

        let desiredState = !contains(podcast: podcast)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.setPodcastSubscribed(
                    podcast,
                    isSubscribed: desiredState
                )
            } catch is CancellationError {
                return
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func setPodcastSubscribed(
        _ podcast: Podcast,
        isSubscribed: Bool
    ) async throws {
        guard isLoggedIn else { throw APIError.notLoggedIn }

        let previousPodcasts = subscribedPodcasts
        let previousTotalCount = subscribedPodcastTotalCount
        let previousNextOffset = subscribedPodcastsNextOffset
        let previousHasMore = hasMoreSubscribedPodcasts
        setLocalPodcast(podcast, isSubscribed: isSubscribed)

        do {
            try await api.setPodcastSubscribed(
                id: podcast.id,
                isSubscribed: isSubscribed
            )
        } catch {
            subscribedPodcasts = previousPodcasts
            subscribedPodcastTotalCount = previousTotalCount
            subscribedPodcastsNextOffset = previousNextOffset
            hasMoreSubscribedPodcasts = previousHasMore
            throw error
        }
    }

    func canDelete(_ playlist: Playlist) -> Bool {
        guard isLoggedIn, let userID = profile?.id else { return false }
        return playlist.creator?.userID == userID && playlist.id != likedPlaylistID
    }

    func deletePlaylist(_ playlist: Playlist) async throws {
        guard isLoggedIn else { throw APIError.notLoggedIn }
        guard canDelete(playlist) else { throw LibraryOperationError.playlistIsNotOwned }
        try await api.deletePlaylist(id: playlist.id)
        favoritePlaylists.removeAll { $0.id == playlist.id }
    }

    func createPlaylist(name: String, isPrivate: Bool) async throws {
        guard isLoggedIn, let profile else { throw APIError.notLoggedIn }
        let created = try await api.createPlaylist(name: name, isPrivate: isPrivate)
        let summary = Playlist(
            id: created.id,
            name: created.name,
            coverURLString: created.coverURLString,
            creator: UserSummary(userID: profile.id, nickname: profile.nickname)
        )
        favoritePlaylists.insert(summary, at: 0)
    }

    func remove(song: Song, from playlist: Playlist) async throws {
        guard isLoggedIn else { throw APIError.notLoggedIn }
        guard canDelete(playlist) else { throw LibraryOperationError.playlistIsNotOwned }
        try await api.removeSong(id: song.id, fromPlaylistID: playlist.id)
        if let index = favoritePlaylists.firstIndex(where: { $0.id == playlist.id }) {
            favoritePlaylists[index].removeSong(id: song.id)
        }
    }

    func add(song: Song, to playlist: Playlist) async throws {
        guard isLoggedIn else { throw APIError.notLoggedIn }
        guard playlist.creator?.userID == profile?.id else {
            throw LibraryOperationError.playlistIsNotOwned
        }
        try await api.addSong(id: song.id, toPlaylistID: playlist.id)
    }

    func clearAccountData() {
        if let cookie = contentCookie { favoriteCache.clear(for: cookie) }
        loadedCookie = nil
        clearRemoteContent()
        phase = .loaded
        errorMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    private func clearRemoteContent() {
        activeRefreshID = nil
        refreshingCookie = nil
        contentCookie = nil
        favoriteSongPageLoadTask?.cancel()
        favoriteSongPageLoadTask = nil
        favoriteSongPageLoadID = nil
        subscribedPodcastPageLoadTask?.cancel()
        subscribedPodcastPageLoadTask = nil
        subscribedPodcastPageLoadID = nil
        profile = nil
        accountDetail = nil
        favoriteSongs = []
        favoritePlaylists = []
        favoriteAlbums = []
        favoriteArtists = []
        subscribedPodcasts = []
        recentSongs = []
        likedPlaylistID = nil
        favoriteSongIDs = []
        favoriteSongIDSet = []
        favoriteSongTotalCount = 0
        favoriteSongsNextOffset = 0
        isLoadingMoreFavoriteSongs = false
        favoriteSongsLoadMoreError = nil
        subscribedPodcastTotalCount = 0
        subscribedPodcastsNextOffset = 0
        hasMoreSubscribedPodcasts = false
        isLoadingMoreSubscribedPodcasts = false
        subscribedPodcastsLoadMoreError = nil
    }

    private func setLocalSong(
        _ song: Song,
        isLiked: Bool
    ) {
        if let index = favoriteSongIDs.firstIndex(of: song.id) {
            favoriteSongIDs.remove(at: index)
            if index < favoriteSongsNextOffset {
                favoriteSongsNextOffset -= 1
            }
        }
        favoriteSongIDSet.remove(song.id)
        favoriteSongs.removeAll { $0.id == song.id }

        if isLiked {
            favoriteSongIDs.insert(song.id, at: 0)
            favoriteSongIDSet.insert(song.id)
            favoriteSongs.insert(song, at: 0)
            favoriteSongsNextOffset += 1
        }
        favoriteSongTotalCount = favoriteSongIDs.count
        persistFavoriteCache()
    }

    private func setLocalPodcast(
        _ podcast: Podcast,
        isSubscribed: Bool
    ) {
        let wasSubscribed =
            contains(podcast: podcast) || podcast.isSubscribed
        subscribedPodcasts.removeAll { $0.id == podcast.id }

        if isSubscribed {
            var summary = podcast
            summary.isSubscribed = true
            subscribedPodcasts.insert(summary, at: 0)
        }

        if wasSubscribed != isSubscribed {
            subscribedPodcastTotalCount += isSubscribed ? 1 : -1
        }
        subscribedPodcastTotalCount = max(
            subscribedPodcastTotalCount,
            subscribedPodcasts.count
        )
        subscribedPodcastsNextOffset = subscribedPodcasts.count
        hasMoreSubscribedPodcasts =
            subscribedPodcastsNextOffset < subscribedPodcastTotalCount
    }

    private func normalizedSubscribedPodcasts(
        _ podcasts: [Podcast]
    ) -> [Podcast] {
        var identifiers = Set<Int>()
        return podcasts.compactMap { podcast in
            guard podcast.id > 0,
                  identifiers.insert(podcast.id).inserted else {
                return nil
            }
            var subscribedPodcast = podcast
            subscribedPodcast.isSubscribed = true
            return subscribedPodcast
        }
    }
}

private enum LibraryOperationError: LocalizedError {
    case playlistIsNotOwned

    var errorDescription: String? {
        switch self {
        case .playlistIsNotOwned:
            L10n.string("ui.library.error.owned_playlist_only")
        }
    }
}
