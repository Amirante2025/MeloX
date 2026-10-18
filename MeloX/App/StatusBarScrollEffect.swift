import SwiftUI
import UIKit

/// Root pages hide the navigation bar, so they need their own scroll-aware
/// system material behind the status bar.
struct StatusBarScrollEffect: ViewModifier {
    @State private var visibility: CGFloat = 0

    func body(content: Content) -> some View {
        content
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
                                        .init(color: .black, location: 0.65),
                                        .init(color: .clear, location: 1),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                            .frame(height: inset + 4)
                            .offset(y: -originY)
                            .opacity(visibility)
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
