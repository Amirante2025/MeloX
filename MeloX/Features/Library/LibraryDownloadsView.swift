import SwiftUI

struct LibraryDownloadsView: View {
    @Environment(\.scrollingPageHeader) private var pageHeader
    let searchQuery: String

    @Environment(DownloadStore.self) private var downloads
    @Environment(PlayerStore.self) private var player

    var body: some View {
        List {
            if pageHeader != nil {
                ScrollingPageListHeader()
            }

            if !filteredDownloadedSongs.isEmpty {
                Button {
                    Task { await player.playAll(filteredDownloadedSongs) }
                } label: {
                    HStack {
                        Label(
                            isSearching
                                ? L10n.string("ui.common.play_search_results")
                                : L10n.string("ui.common.play_all"),
                            systemImage: "play.fill"
                        )
                        Spacer()
                    }
                }
            }

            if !isSearching {
                NavigationLink {
                    DownloadsView()
                        .environment(\.scrollingPageHeader, nil)
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    HStack {
                        Label("ui.downloads.management", systemImage: "arrow.down.circle")
                        Spacer()
                        Text(downloadManagementValue)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .listRowSeparator(.hidden, edges: .bottom)
            }

            if !activeDownloadSongs.isEmpty {
                Section("ui.downloads.active") {
                    ForEach(activeDownloadSongs) { song in
                        TrackRowView(song: song, showsArtwork: true)
                            .swipeActions {
                                Button(role: .destructive) {
                                    downloads.cancel(songID: song.id)
                                } label: {
                                    Label("ui.common.cancel", systemImage: "xmark")
                                }
                            }
                    }
                }
            }

            ForEach(filteredDownloads) { download in
                Button {
                    Task {
                        await player.play(
                            download.song,
                            in: filteredDownloadedSongs
                        )
                    }
                } label: {
                    TrackRowView(song: download.song, showsArtwork: true)
                }
                .buttonStyle(.plain)
                .compactSongListRow()
                .listRowSeparator(
                    !isSearching && activeDownloadSongs.isEmpty
                        && download.id == filteredDownloads.first?.id ? .hidden : .automatic,
                    edges: .top
                )
                .swipeActions {
                    Button(role: .destructive) {
                        downloads.remove(songID: download.id)
                    } label: {
                        Label("ui.downloads.delete", systemImage: "trash")
                    }
                }
            }
        }
        .modifier(NativeStatusBarScrollEffect())
        .listStyle(.plain)
        .overlay {
            if filteredDownloads.isEmpty,
               activeDownloadSongs.isEmpty {
                if isSearching {
                    ContentUnavailableView.search(
                        text: normalizedSearchQuery
                    )
                } else {
                    ContentUnavailableView(
                        "ui.downloads.empty",
                        systemImage: "arrow.down.circle",
                        description: Text(
                            "ui.downloads.empty.message"
                        )
                    )
                }
            }
        }
    }

    private var normalizedSearchQuery: String {
        normalizedLibrarySearchQuery(searchQuery)
    }

    private var isSearching: Bool {
        !normalizedSearchQuery.isEmpty
    }

    private var activeDownloadSongs: [Song] {
        filterMusicCollectionTracks(
            Array(downloads.activeSongs.values),
            query: normalizedSearchQuery
        ).sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    private var filteredDownloads: [DownloadedSong] {
        let songIDs = Set(
            filterMusicCollectionTracks(
                downloads.downloadedSongs,
                query: normalizedSearchQuery
            ).map(\.id)
        )
        return downloads.downloads.filter { songIDs.contains($0.id) }
    }

    private var filteredDownloadedSongs: [Song] {
        filteredDownloads.map(\.song)
    }

    private var downloadManagementValue: String {
        if !downloads.activeDownloads.isEmpty {
            return L10n.format("ui.downloads.active_count", downloads.activeDownloads.count)
        }
        return L10n.byteCount(downloads.totalByteCount)
    }
}
