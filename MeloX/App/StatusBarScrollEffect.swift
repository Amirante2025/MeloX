import SwiftUI
import UIKit

@MainActor
enum RootPageSafeArea {
    static var topInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }
}

private struct StatusBarRootActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isStatusBarRootActive: Bool {
        get { self[StatusBarRootActiveKey.self] }
        set { self[StatusBarRootActiveKey.self] = newValue }
    }
}

/// Extend the scroll viewport under the status bar, keeping its initial inset.
/// Draw the blur outside the List's clipping view.
struct NativeStatusBarScrollEffect: ViewModifier {
    @Environment(\.scrollingPageHeader) private var pageHeader
    @Environment(\.isStatusBarRootActive) private var isRootActive
    @State private var visibility: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if pageHeader != nil {
            GeometryReader { geometry in
                let topInset = max(geometry.safeAreaInsets.top, RootPageSafeArea.topInset)
                content
                    .safeAreaPadding(.top, topInset)
                    .ignoresSafeArea(.container, edges: .top)
                    .scrollClipDisabled()
                    .scrollEdgeEffectHidden(true, for: .top)
                    .onScrollGeometryChange(for: CGFloat.self) { scroll in
                        let distance = scroll.contentOffset.y + scroll.contentInsets.top
                        return min(1, max(0, (distance - 2) / 22))
                    } action: { _, value in
                        visibility = value
                    }
                    .background {
                        StatusBarWindowBlur(
                            isActive: isRootActive,
                            visibility: visibility
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
            }
        } else {
            content
        }
    }

}

struct StatusBarScrollEffect: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(NativeStatusBarScrollEffect())
    }
}

private struct StatusBarWindowBlur: UIViewRepresentable {
    let isActive: Bool
    let visibility: CGFloat

    func makeUIView(context: Context) -> StatusBarBlurAnchorView {
        StatusBarBlurAnchorView()
    }

    func updateUIView(_ view: StatusBarBlurAnchorView, context: Context) {
        view.update(isActive: isActive, visibility: visibility)
    }

    static func dismantleUIView(_ view: StatusBarBlurAnchorView, coordinator: ()) {
        view.detachBlur()
    }
}

private final class StatusBarBlurAnchorView: UIView {
    private let blur = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterial)
    )
    private let gradientMask = StatusBarGradientMaskView()
    private var isActive = false
    private var visibility: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        blur.isUserInteractionEnabled = false
        blur.accessibilityElementsHidden = true
        gradientMask.isOpaque = false
        gradientMask.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncBlur()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncBlur()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        syncBlur()
    }

    func update(isActive: Bool, visibility: CGFloat) {
        self.isActive = isActive
        self.visibility = visibility
        syncBlur()
    }

    func detachBlur() {
        blur.removeFromSuperview()
    }

    private func syncBlur() {
        guard isActive, visibility > 0,
              let window, window.safeAreaInsets.top > 0,
              let host = window.rootViewController?.view else {
            detachBlur()
            return
        }

        if blur.superview !== host {
            host.addSubview(blur)
        }
        if host.subviews.last !== blur {
            host.bringSubviewToFront(blur)
        }
        blur.frame = host.convert(
            CGRect(
                x: window.bounds.minX,
                y: window.bounds.minY,
                width: window.bounds.width,
                height: window.safeAreaInsets.top + 4
            ),
            from: window
        )
        gradientMask.frame = blur.bounds
        gradientMask.update(visibility: visibility)
        // Keep the effect view fully opaque. A direct mask fades the native
        // effect without the offscreen compositing caused by view alpha.
        blur.mask = nil
        blur.mask = gradientMask
    }
}

private final class StatusBarGradientMaskView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    func update(visibility: CGFloat) {
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.65 * visibility).cgColor,
            UIColor.black.withAlphaComponent(0.35 * visibility).cgColor,
            UIColor.clear.cgColor,
        ]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
    }
}
