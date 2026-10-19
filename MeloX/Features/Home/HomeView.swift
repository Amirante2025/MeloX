import SwiftUI

struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.scrollingPageHeader) private var pageHeader

    @State private var section = AppTab.recommended

    private var availableSections: [AppTab] {
        settings.homeTabs
    }

    private var activeSection: AppTab? {
        availableSections.contains(section)
            ? section
            : availableSections.first
    }

    private var sectionSelection: Binding<AppTab> {
        Binding(
            get: { activeSection ?? .recommended },
            set: { section = $0 }
        )
    }

    var body: some View {
        Group {
            if let activeSection {
                sectionContent(for: activeSection)
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        ScrollingPageHeader()
                        ContentUnavailableView(
                            "ui.home.no_visible_pages.title",
                            systemImage: "rectangle.3.group",
                            description: Text("ui.home.no_visible_pages.message")
                        )
                    }
                }
                .modifier(StatusBarScrollEffect())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.scrollingPageHeader, homeHeader)
        .onChange(of: availableSections) { _, sections in
            guard !sections.contains(section) else { return }
            section = sections.first ?? .recommended
        }
    }

    private var homeHeader: AnyView? {
        guard let pageHeader else { return nil }
        return AnyView(
            VStack(spacing: 8) {
                pageHeader
                if availableSections.count > 1 {
                    sectionPicker
                }
            }
        )
    }

    @ViewBuilder
    private var sectionPicker: some View {
        if availableSections.count <= 4 {
            Picker("ui.home.section_picker", selection: sectionSelection) {
                ForEach(availableSections) { section in
                    Text(section.settingsTitle)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 8)
        } else {
            Picker("ui.home.section_picker", selection: sectionSelection) {
                ForEach(availableSections) { section in
                    Label(
                        section.settingsTitle,
                        systemImage: section.systemImage
                    )
                    .tag(section)
                }
            }
            .pickerStyle(.menu)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func sectionContent(
        for section: AppTab
    ) -> some View {
        switch section {
        case .recommended:
            HomeRecommendedView()
        case .music:
            ExploreView(showsNavigationTitle: false)
        case .podcasts:
            PodcastHomeView(showsNavigationTitle: false)
        case .explore:
            ExploreView(showsNavigationTitle: false)
        case .library:
            LibraryView(showsNavigationTitle: false)
        case .librarySongs,
             .libraryPlaylists,
             .libraryAlbums,
             .libraryArtists,
             .libraryPodcasts,
             .libraryDownloads,
             .libraryCloud,
             .libraryHistory:
            if let page = section.libraryPage {
                LibraryView(
                    fixedPage: page,
                    showsNavigationTitle: false
                )
            }
        case .home,
             .search:
            EmptyView()
        }
    }
}
