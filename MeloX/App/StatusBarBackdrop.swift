import SwiftUI
import UIKit

struct StatusBarBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            let originY = geometry.frame(in: .global).minY
            let statusHeight = max(
                geometry.safeAreaInsets.top,
                max(originY, windowStatusHeight)
            )
            if statusHeight > 0 {
                let height = statusHeight + 16
                Rectangle()
                    .fill(.regularMaterial)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(
                                    color: .black,
                                    location: max(0, (statusHeight - 16) / height)
                                ),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .frame(height: height)
                    .offset(y: -originY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var windowStatusHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }
}
