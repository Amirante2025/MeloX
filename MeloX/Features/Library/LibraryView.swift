import SwiftUI

struct LibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(\.scrollingPageHeader) private var pageHeader

    private let fixedPage: LibraryPage?
    private let showsNavigationTitle: Bool

    @State private var section: LibraryPage
    @State private var hasAppliedInitialPage = false
    @State private var showsLogin = false
    @State private var searchQuery = ""

    init(
        fixedPage: LibraryPage? = nil,
        showsNavigationTitle: Bool = true
    ) {
        let resolvedFixedPage = fixedPage.flatMap { page in
            LibraryPage.availableCases.contains(page) ? page : nil
        }
        self.fixedPage = resolvedFixedPage
        self.showsNavigationTitle = showsNavigationTitle
        _section = State(initialValue: resolvedFixedPage ?? .songs)
    }

    private var availablePages: [LibraryPage] {
        fixedPage.map { [$0] } ?? settings.embeddedLibraryPages
    }

    var body: some View {
        VStack(spacing: 0) {
            if pageHeader == nil, !showsNavigationTitle,
               fixedPage == nil, availablePages.count > 1 {
                Group {
                    if availablePages.count > 4, horizontalSizeClass == .compact {
                        pagePicker.pickerStyle(.menu)
                    } else {
                        pagePicker.pickerStyle(.segmented)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.background)
            }

            if availablePages.isEmpty {
                placeholder {
                    ContentUnavailableView(
                        "ui.library.pages_separated.title",
                        systemImage: "rectangle.3.group",
                        description: Text("ui.library.pages_separated.message")
                    )
                }
            } else if section == .downloads {
                LibraryDownloadsView(searchQuery: searchQuery)
            } else if !library.isLoggedIn {
                placeholder { loginUnavailableView }
            } else if section == .cloud {
                CloudMusicView(searchQuery: searchQuery)
            } else {
                libraryContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.scrollingPageHeader, libraryHeader)
        .libraryNavigationTitle(
            fixedPage.map { AppTab(libraryPage: $0).title }
                ?? L10n.string("ui.navigation.library"),
            isPresented: showsNavigationTitle && pageHeader == nil
        )
        .librarySearchable(
            text: $searchQuery,
            prompt: searchPrompt,
            isEnabled: canSearchCurrentPage && pageHeader == nil
        )
        .toolbar {
            if pageHeader == nil, showsNavigationTitle,
               fixedPage == nil, availablePages.count > 1 {
                ToolbarTitleMenu {
                    pagePicker.pickerStyle(.inline)
                }
            }
        }
        .onAppear {
            guard !hasAppliedInitialPage else { return }
            hasAppliedInitialPage = true
            if let fixedPage {
                section = fixedPage
            } else {
                section = availablePages.contains(settings.initialLibraryPage)
                    ? settings.initialLibraryPage
                    : availablePages.first ?? .songs
            }
        }
        .onChange(of: section) { _, page in
            if fixedPage == nil {
                settings.lastLibraryPage = page
            }
        }
        .onChange(of: settings.contentFeatures.showsLibrarySearch) { _, showsSearch in
            if !showsSearch {
                searchQuery = ""
            }
        }
        .onChange(of: availablePages) { _, pages in
            guard fixedPage == nil,
                  let firstPage = pages.first,
                  !pages.contains(section) else {
                return
            }
            section = firstPage
        }
        .sheet(isPresented: $showsLogin) {
            NavigationStack {
                NeteaseLoginView()
            }
        }
        .task(id: settings.cookie) {
            await library.refresh()
        }
        .alert(
            "ui.library.error.title",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { presented in
                    if !presented {
                        library.clearError()
                    }
                }
            )
        ) {
            Button("ui.common.ok", role: .cancel) {
                library.clearError()
            }
        } message: {
            Text(library.errorMessage ?? L10n.string("ui.common.unknown_error"))
        }
    }

    private var libraryHeader: AnyView? {
        guard let pageHeader else { return nil }
        return AnyView(
            VStack(spacing: 12) {
                pageHeader
                if fixedPage == nil, availablePages.count > 1 {
                    if availablePages.count > 4 {
                        pagePicker.pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        pagePicker.pickerStyle(.segmented)
                    }
                }
                if canSearchCurrentPage {
                    librarySearchField
                }
            }
        )
    }

    private var librarySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(searchPrompt, text: $searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("library-search")
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ui.common.clear")
            }
        }
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 12))
    }

    private func placeholder<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                ScrollingPageHeader()
                content().frame(minHeight: 320)
            }
        }
    }

    private var pagePicker: some View {
        Picker("ui.library.category_picker", selection: $section) {
            ForEach(availablePages) { item in
                Text(item.title).tag(item)
            }
        }
    }

    private var loginUnavailableView: some View {
        ContentUnavailableView {
            Label("ui.account.login_required", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text(
                AppFeatureAvailability.downloads
                    ? L10n.string("ui.library.login_message.downloads")
                    : L10n.string("ui.library.login_message")
            )
        } actions: {
            Button("ui.account.login_netease") {
                showsLogin = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch library.phase {
        case .loading where library.profile == nil:
            placeholder { ProgressView("ui.library.loading") }
        case .failed(let message) where library.profile == nil:
            placeholder {
                ConnectionUnavailableView(message: message) {
                    Task { await library.refresh(force: true) }
                }
            }
        default:
            switch section {
            case .songs:
                LibrarySongsView(searchQuery: searchQuery)
            case .playlists:
                LibraryPlaylistsView(searchQuery: searchQuery)
            case .artists:
                LibraryArtistsView(searchQuery: searchQuery)
            case .albums:
                LibraryAlbumsView(searchQuery: searchQuery)
            case .podcasts:
                SubscribedPodcastsView(searchQuery: searchQuery)
            case .downloads:
                LibraryDownloadsView(searchQuery: searchQuery)
            case .cloud:
                CloudMusicView(searchQuery: searchQuery)
            case .history:
                LibraryHistoryView(searchQuery: searchQuery)
            }
        }
    }

    private var canSearchCurrentPage: Bool {
        settings.contentFeatures.showsLibrarySearch
            && !availablePages.isEmpty
            && (section == .downloads || library.isLoggedIn)
    }

    private var searchPrompt: String {
        switch section {
        case .songs:
            L10n.string("ui.library.search.favorite_songs")
        case .playlists:
            L10n.string("ui.library.search.favorite_playlists")
        case .artists:
            L10n.string("ui.library.artists.search")
        case .albums:
            L10n.string("ui.library.search.favorite_albums")
        case .podcasts:
            L10n.string("ui.library.search.subscribed_podcasts")
        case .downloads:
            AppFeatureAvailability.downloads
                ? L10n.string("ui.library.search.downloads")
                : L10n.string("ui.library.search.songs")
        case .cloud:
            L10n.string("ui.library.search.cloud")
        case .history:
            L10n.string("ui.library.search.history")
        }
    }
}

private extension View {
    @ViewBuilder
    func libraryNavigationTitle(
        _ title: String,
        isPresented: Bool
    ) -> some View {
        if isPresented {
            navigationTitle(title)
        } else {
            self
        }
    }

    @ViewBuilder
    func librarySearchable(
        text: Binding<String>,
        prompt: String,
        isEnabled: Bool
    ) -> some View {
        if isEnabled {
            searchable(
                text: text,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(prompt)
            )
        } else {
            self
        }
    }
}
