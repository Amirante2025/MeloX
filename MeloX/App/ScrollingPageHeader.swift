import SwiftUI

private struct ScrollingPageHeaderKey: EnvironmentKey {
    static let defaultValue: AnyView? = nil
}

extension EnvironmentValues {
    var scrollingPageHeader: AnyView? {
        get { self[ScrollingPageHeaderKey.self] }
        set { self[ScrollingPageHeaderKey.self] = newValue }
    }
}

/// Inserted inside a page's ScrollView or List so its title and account actions
/// scroll with the content instead of occupying a navigation bar.
struct ScrollingPageHeader: View {
    @Environment(\.scrollingPageHeader) private var header
    var horizontalPadding: CGFloat = 16

    var body: some View {
        if let header {
            header
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ScrollingPageListHeader: View {
    @Environment(\.scrollingPageHeader) private var header

    var body: some View {
        if header != nil {
            ScrollingPageHeader(horizontalPadding: 0)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }
}
