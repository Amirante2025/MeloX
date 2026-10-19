import SwiftUI
import UIKit

/// Register a native top bar even when the page hides its navigation bar.
/// The transparent, one-pixel bar extends the system scroll edge effect into
/// the status-bar safe area without pinning the page title or adding a tint.
struct NativeStatusBarScrollEffect: ViewModifier {
    @Environment(\.scrollingPageHeader) private var pageHeader
    @Environment(\.displayScale) private var displayScale
    @State private var hasScrolled = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if pageHeader != nil {
            content
                .safeAreaBar(edge: .top, spacing: 0) {
                    Color.clear
                        .frame(height: 1 / max(displayScale, 1))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectHidden(!hasScrolled, for: .top)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 2
                } action: { _, value in
                    hasScrolled = value
                }
        } else {
            content
        }
    }
}

/// Root pages hide the navigation bar, so they need their own scroll-aware
/// system material behind the status bar.
/// Apply directly to the vertical ScrollView or List, not its page container.
struct StatusBarScrollEffect: ViewModifier {
    @Environment(\.scrollingPageHeader) private var pageHeader
    @State private var visibility: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if pageHeader != nil {
            scrollingContent(content)
        } else {
            content
        }
    }

    private func scrollingContent(_ content: Content) -> some View {
        content
            .scrollClipDisabled()
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let distance = geometry.contentOffset.y + geometry.contentInsets.top
                return min(1, max(0, (distance - 2) / 22))
            } action: { _, value in
                visibility = value
            }
            .overlay(alignment: .top) {
                GeometryReader { geometry in
                    let originY = geometry.frame(in: .global).minY
                    let inset = max(geometry.safeAreaInsets.top, windowTopInset)
                    if inset > 0 {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .mask {
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black.opacity(0.55), location: 0.45),
                                        .init(color: .clear, location: 1),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                            .frame(height: inset + 4)
                            .offset(y: -originY)
                            .opacity(visibility * 0.28)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }

    private var windowTopInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }
}
