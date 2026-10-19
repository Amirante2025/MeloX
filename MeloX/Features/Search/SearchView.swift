import SwiftUI

struct SearchView: View {
    @Environment(\.scrollingPageHeader) private var pageHeader
    @Environment(NeteaseAPI.self) private var api
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings

    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var searchSubmissionID = 0
    @State private var isSearchFocused = false
    @State private var searchControlsTop: CGFloat?
    @State private var searchControlsHeight: CGFloat = 48
    @State private var viewportHeight: CGFloat = 0
    @State private var suggestions: [String] = []
    @State private var suggestionsPhase: LoadingPhase = .loaded
    @State private var suggestionRetryID = 0
    @State private var resultCache = SearchResultCache()
    @State private var scope: SearchKind = .songs
    @State private var phase: LoadingPhase = .loaded
    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var playlists: [Playlist] = []
    @State private var podcasts: [Podcast] = []
    @State private var completedRequest: SearchRequest?
    @State private var recognizedLink: NeteaseMusicLink?
    @State private var linkedSong: Song?
    @State private var presentedListenTogetherLink:
        NeteaseListenTogetherLink?

    @State private var discoveryRecommendations: [Playlist] = []
    @State private var discoveryPhase: LoadingPhase = .loading

    private enum ScrollAnchor: Hashable {
        case searchContent
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                List {
                    if pageHeader != nil {
                        ScrollingPageListHeader()
                    }

                    Section {
                        Color.clear
                            .frame(height: 1)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .accessibilityHidden(true)
                            .id(ScrollAnchor.searchContent)

                        if showsSuggestions {
                            suggestionRows
                        }

                        if showsSearchResults {
                            if let recognizedLink {
                                linkResult(for: recognizedLink)
                            } else {
                                searchResults
                            }
                        } else if trimmedQuery.isEmpty || (!isSearchFocused && !showsSuggestions) {
                            SearchDiscoveryView(
                                recommendations: discoveryRecommendations,
                                phase: discoveryPhase,
                                onRetry: {
                                    Task { await loadDiscoveryRecommendations() }
                                }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }

                        if isSearchFocused || showsSearchResults || showsSuggestions {
                            Color.clear
                                .frame(height: minimumResultsSpacer)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .accessibilityHidden(true)
                        }
                    } header: {
                        searchControlsPlaceholder
                            .textCase(nil)
                            .listRowInsets(
                                EdgeInsets(top: 0, leading: 12, bottom: 8, trailing: 12)
                            )
                    }
                }
                .modifier(StatusBarScrollEffect())
                .listStyle(.plain)
                .listSectionSpacing(0)
                .environment(\.defaultMinListRowHeight, 1)
                .scrollDismissesKeyboard(.interactively)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { viewportHeight = $0 }
                .refreshable {
                    if !showsSearchResults {
                        await loadDiscoveryRecommendations()
                    }
                }

                // Keep the UIKit input outside reusable List headers. Result
                // and suggestion updates must not recreate the first responder.
                searchControls
                    .padding(.horizontal, 12)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { searchControlsHeight = $0 }
                    .offset(
                        y: max(
                            pageHeader == nil ? 0 : RootPageSafeArea.topInset,
                            searchControlsTop ?? 0
                        )
                    )
                    .opacity(searchControlsTop == nil ? 0 : 1)
                    .allowsHitTesting(searchControlsTop != nil)
            }
            .coordinateSpace(name: "music-search-page")
            .onChange(of: isSearchFocused) { _, focused in
                guard focused else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(ScrollAnchor.searchContent, anchor: .top)
                }
            }
        }
        .navigationTitle("ui.navigation.search")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDiscoveryRecommendations()
        }
        .task(id: "\(showsSuggestions):\(trimmedQuery):\(suggestionRetryID)") {
            await loadSuggestions()
        }
        .overlay {
            if showsSearchResults, case .failed(let message) = phase {
                ContentUnavailableView(
                    recognizedLink == nil
                        ? L10n.string("ui.search.failed")
                        : L10n.string("ui.search.link_failed"),
                    systemImage: recognizedLink == nil
                        ? "exclamationmark.magnifyingglass"
                        : "link.badge.plus",
                    description: Text(message)
                )
                .allowsHitTesting(false)
            } else if recognizedLink == nil,
                      showsSearchResults,
                      phase == .loaded,
                      resultIsEmpty {
                ContentUnavailableView.search(text: submittedQuery)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $presentedListenTogetherLink) { invitation in
            ListenTogetherView(
                invitationText: invitation.invitationText
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "ui.error.favorite_failed",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.clearError() } }
            )
        ) {
            Button("ui.common.ok", role: .cancel) {
                library.clearError()
            }
        } message: {
            Text(library.errorMessage ?? L10n.string("ui.common.unknown_error"))
        }
        .task(id: searchRequest) {
            let request = searchRequest
            guard completedRequest != request else { return }
            await search(request)
        }
        .onChange(of: query) { _, value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                submittedQuery = ""
            }
        }
        .onChange(
            of: settings.isContentFeatureEnabled(.podcasts)
        ) { _, podcastsEnabled in
            if !podcastsEnabled, scope == .podcasts {
                scope = .songs
            }
        }
    }

    private var searchControls: some View {
        VStack(spacing: 8) {
            NativeSearchBar(
                text: $query,
                isFocused: $isSearchFocused,
                onSubmit: { submitSearch() },
                onCancel: cancelSearch
            )
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .padding(.top, -8)

            if showsSearchResults {
                Picker("ui.navigation.search", selection: $scope) {
                    ForEach(availableSearchKinds) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var searchControlsPlaceholder: some View {
        Color.clear
            .frame(height: searchControlsHeight)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.frame(in: .named("music-search-page")).minY
            } action: { searchControlsTop = max(0, $0) }
            .accessibilityHidden(true)
    }

    private var showsSearchResults: Bool {
        !isSearchFocused && !submittedQuery.isEmpty && submittedQuery == trimmedQuery
    }

    private var showsSuggestions: Bool {
        settings.searchSuggestionsEnabled && !trimmedQuery.isEmpty
            && (isSearchFocused || submittedQuery != trimmedQuery)
            && NeteaseMusicLinkParser.parse(trimmedQuery) == nil
    }

    @ViewBuilder
    private var suggestionRows: some View {
        if suggestionsPhase == .loading {
            HStack(spacing: 12) {
                ProgressView()
                Text("ui.search.suggestions_loading")
                    .foregroundStyle(.secondary)
            }
        } else if case .failed = suggestionsPhase {
            HStack {
                Label("ui.search.suggestions_failed", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("ui.common.retry") {
                    suggestionRetryID += 1
                }
                .buttonStyle(.borderless)
            }
        }

        ForEach(suggestions, id: \.self) { suggestion in
            Button {
                submitSearch(suggestion)
            } label: {
                Label {
                    Text(verbatim: suggestion)
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search-suggestion-\(suggestion)")
        }
    }

    private var searchRequest: SearchRequest {
        SearchRequest(
            query: submittedQuery,
            kind: scope,
            submissionID: searchSubmissionID
        )
    }

    private func submitSearch(_ suggestion: String? = nil) {
        let keywords = (suggestion ?? query)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keywords.isEmpty else { return }
        query = keywords
        submittedQuery = keywords
        searchSubmissionID += 1
        suggestions = []
        isSearchFocused = false
    }

    private func cancelSearch() {
        query = ""
        submittedQuery = ""
        suggestions = []
        isSearchFocused = false
    }

    // Short result sets still need enough scrollable space for the title to
    // leave the screen without pushing the focused search field back down.
    private var minimumResultsSpacer: CGFloat {
        let resultCount: Int
        if isSearchFocused || showsSuggestions {
            resultCount = 0
        } else if recognizedLink != nil {
            resultCount = linkedSong == nil ? 0 : 1
        } else {
            switch scope {
            case .songs: resultCount = songs.count
            case .albums: resultCount = albums.count
            case .artists: resultCount = artists.count
            case .playlists: resultCount = playlists.count
            case .podcasts: resultCount = podcasts.count
            }
        }
        let suggestionCount = showsSuggestions
            ? suggestions.count : 0
        return max(0, viewportHeight - 56 - CGFloat(resultCount + suggestionCount) * 44)
    }

    private func loadDiscoveryRecommendations() async {
        discoveryPhase = .loading
        do {
            let recommendations = try await api.recommendedPlaylists(limit: 10)
            try Task.checkCancellation()
            discoveryRecommendations = recommendations
            discoveryPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            discoveryPhase = .failed(error.localizedDescription)
        }
    }

    private func loadSuggestions() async {
        suggestions = []
        suggestionsPhase = .loaded
        let keywords = trimmedQuery
        guard showsSuggestions else { return }
        suggestionsPhase = .loading
        do {
            try await Task.sleep(for: .milliseconds(300))
            let loaded = try await api.searchSuggestions(keywords)
            try Task.checkCancellation()
            guard showsSuggestions, keywords == trimmedQuery else { return }
            suggestions = loaded
            suggestionsPhase = .loaded
        } catch {
            guard !Task.isCancelled, showsSuggestions, keywords == trimmedQuery else { return }
            suggestionsPhase = .failed(error.localizedDescription)
        }
    }

    private var availableSearchKinds: [SearchKind] {
        SearchKind.allCases.filter {
            $0 != .podcasts
                || settings.isContentFeatureEnabled(.podcasts)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if phase == .loading {
            HStack {
                Spacer()
                ProgressView("ui.search.searching")
                Spacer()
            }
        }

        switch scope {
        case .songs:
            ForEach(songs) { song in
                Button {
                    Task { await player.play(song, in: songs) }
                } label: {
                    TrackRowView(song: song, showsArtwork: true)
                }
                .buttonStyle(.plain)
                .compactSongListRow()
                .swipeActions(edge: .trailing) {
                    Button {
                        library.toggle(song: song)
                    } label: {
                        Label(
                            library.contains(song: song)
                                ? L10n.string("ui.common.unfavorite")
                                : L10n.string("ui.common.favorite"),
                            systemImage: library.contains(song: song) ? "heart.slash" : "heart"
                        )
                    }
                    .tint(.pink)
                }
            }
        case .albums:
            ForEach(albums) { album in
                NavigationLink(value: MusicRoute.album(album)) {
                    SearchMediaRow(
                        title: album.name,
                        subtitle: album.artistText,
                        artworkURL: album.artworkURL,
                        circular: false
                    )
                }
                .musicMatchedTransitionSource(for: MusicRoute.album(album))
            }
        case .artists:
            ForEach(artists) { artist in
                NavigationLink(value: MusicRoute.artist(artist.id)) {
                    SearchMediaRow(
                        title: artist.name,
                        subtitle: artist.aliases.first,
                        artworkURL: artist.artworkURL,
                        circular: true
                    )
                }
                .musicMatchedTransitionSource(for: MusicRoute.artist(artist.id))
            }
        case .playlists:
            ForEach(playlists) { playlist in
                NavigationLink(value: MusicRoute.playlist(playlist)) {
                    SearchMediaRow(
                        title: playlist.name,
                        subtitle: L10n.format("ui.common.song_count", playlist.trackCount),
                        artworkURL: playlist.artworkURL,
                        circular: false
                    )
                }
                .musicMatchedTransitionSource(for: MusicRoute.playlist(playlist))
            }
        case .podcasts:
            ForEach(podcasts) { podcast in
                NavigationLink(
                    value: MusicRoute.podcast(podcast)
                ) {
                    PodcastListRow(podcast: podcast)
                }
            }
        }
    }

    @ViewBuilder
    private func linkResult(for link: NeteaseMusicLink) -> some View {
        switch link {
        case .song:
            if phase == .loading {
                HStack {
                    Spacer()
                    ProgressView("ui.search.reading_song_link")
                    Spacer()
                }
            } else if let linkedSong {
                Text("ui.search.section.linked_song")
                    .font(.headline)
                    .listRowSeparator(.hidden)
                NavigationLink(value: MusicRoute.song(linkedSong)) {
                    TrackRowView(song: linkedSong, showsArtwork: true)
                }
                .compactSongListRow()
                .musicMatchedTransitionSource(for: MusicRoute.song(linkedSong))
            }

        case .listenTogether(let invitation):
            ContentUnavailableView {
                Label("ui.listen_together.invitation", systemImage: "person.2.wave.2")
            } description: {
                Text("ui.search.listen_together_link_recognized")
            } actions: {
                Button("ui.clipboard.view_invitation") {
                    presentedListenTogetherLink = invitation
                }
                .buttonStyle(.borderedProminent)
            }
            .listRowSeparator(.hidden)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resultIsEmpty: Bool {
        switch scope {
        case .songs: songs.isEmpty
        case .albums: albums.isEmpty
        case .artists: artists.isEmpty
        case .playlists: playlists.isEmpty
        case .podcasts: podcasts.isEmpty
        }
    }

    private func search(_ request: SearchRequest) async {
        let keywords = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keywords.isEmpty else {
            clearResults()
            resultCache.clear()
            recognizedLink = nil
            linkedSong = nil
            phase = .loaded
            completedRequest = request
            return
        }

        if let link = NeteaseMusicLinkParser.parse(keywords) {
            await resolve(link, for: request)
            return
        }

        recognizedLink = nil
        linkedSong = nil
        if let cached = resultCache.value(for: keywords, kind: request.kind) {
            apply(cached)
            phase = .loaded
            completedRequest = request
            return
        }
        phase = .loading
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        do {
            let result = try await api.search(keywords, kind: request.kind)
            guard !Task.isCancelled else { return }
            apply(result)

            if request.kind == .songs, !songs.isEmpty {
                let details = try? await api.songDetails(ids: songs.map(\.id))
                guard !Task.isCancelled else { return }
                if let details, !details.isEmpty {
                    songs = details
                }
            }
            resultCache.insert(
                SearchPayload(songs: songs, albums: albums, artists: artists, playlists: playlists, podcasts: podcasts),
                for: keywords,
                kind: request.kind
            )
            phase = .loaded
            completedRequest = request
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func apply(_ result: SearchPayload) {
        songs = result.songs ?? []
        albums = result.albums ?? []
        artists = result.artists ?? []
        playlists = result.playlists ?? []
        podcasts = result.podcasts ?? []
    }

    private func resolve(
        _ link: NeteaseMusicLink,
        for request: SearchRequest
    ) async {
        recognizedLink = link
        linkedSong = nil
        clearResults()

        switch link {
        case .song(let id):
            phase = .loading
            do {
                let details = try await api.songDetails(ids: [id])
                try Task.checkCancellation()
                guard let song = details.first else {
                    phase = .failed(
                        L10n.string("ui.clipboard.error.song_not_found")
                    )
                    return
                }
                linkedSong = song
                phase = .loaded
                completedRequest = request
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(error.localizedDescription)
            }

        case .listenTogether:
            phase = .loaded
            completedRequest = request
        }
    }

    private func clearResults() {
        songs = []
        albums = []
        artists = []
        playlists = []
        podcasts = []
    }
}

private struct SearchRequest: Hashable {
    let query: String
    let kind: SearchKind
    let submissionID: Int
}

private struct SearchMediaRow: View {
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let circular: Bool

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(url: artworkURL, cornerRadius: circular ? 1_000 : 7)
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
