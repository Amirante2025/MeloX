import SwiftUI
import UIKit

// Controls publish their actual frames; spacers and artwork stay draggable.
private struct PlayerDismissalExclusionKey: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func playerDismissalExcluded(
        isEnabled: Bool = true,
        bottomInset: CGFloat = 0
    ) -> some View {
        background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                let excludedFrame = CGRect(
                    x: frame.minX,
                    y: frame.minY,
                    width: frame.width,
                    height: max(frame.height - bottomInset, 0)
                )
                Color.clear
                    .preference(
                        key: PlayerDismissalExclusionKey.self,
                        value: isEnabled && excludedFrame.height > 0
                            ? [excludedFrame] : []
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    // Resident pages and auto-hidden controls must not leave invisible blockers.
    func playerDismissalExclusionsEnabled(_ isEnabled: Bool) -> some View {
        transformPreference(PlayerDismissalExclusionKey.self) { frames in
            if !isEnabled { frames.removeAll() }
        }
    }

    func playerFreeAreaDismissal(
        isTransitionActive: Bool,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(
            PlayerFreeAreaDismissalModifier(
                isTransitionActive: isTransitionActive,
                onDismiss: onDismiss
            )
        )
    }
}

private struct PlayerFreeAreaDismissalModifier: ViewModifier {
    let isTransitionActive: Bool
    let onDismiss: () -> Void
    @State private var excludedFrames: [CGRect] = []

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .onPreferenceChange(PlayerDismissalExclusionKey.self) {
                excludedFrames = $0
            }
            .gesture(
                PlayerFreeAreaDismissalGesture(
                    excludedFrames: excludedFrames,
                    isTransitionActive: isTransitionActive,
                    onDismiss: onDismiss
                )
            )
    }
}

enum PlayerFreeAreaDismissalPolicy {
    static func canBegin(
        at start: CGPoint,
        velocity: CGPoint,
        excludedFrames: [CGRect],
        isTransitionActive: Bool
    ) -> Bool {
        guard !isTransitionActive,
              start.x.isFinite, start.y.isFinite,
              velocity.x.isFinite, velocity.y.isFinite,
              velocity.y > abs(velocity.x) * 1.2 else { return false }
        return !excludedFrames.contains {
            $0.insetBy(dx: -4, dy: -4).contains(start)
        }
    }

    static func shouldDismiss(
        translation: CGPoint,
        velocity: CGPoint,
        isTransitionActive: Bool
    ) -> Bool {
        guard !isTransitionActive,
              translation.x.isFinite, translation.y.isFinite,
              velocity.x.isFinite, velocity.y.isFinite,
              velocity.y >= 0,
              translation.y > abs(translation.x) * 1.2 else { return false }
        let isDownwardFlick = translation.y >= 24
            && velocity.y >= 700
            && velocity.y > abs(velocity.x) * 1.2
        return translation.y >= 90 || isDownwardFlick
    }
}

private struct PlayerFreeAreaDismissalGesture: UIGestureRecognizerRepresentable {
    let excludedFrames: [CGRect]
    let isTransitionActive: Bool
    let onDismiss: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        configure(context.coordinator)
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        configure(context.coordinator)
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        guard recognizer.state == .ended,
              !context.coordinator.didRequestDismiss,
              PlayerFreeAreaDismissalPolicy.shouldDismiss(
                translation: context.converter.translation(in: .global) ?? .zero,
                velocity: context.converter.velocity(in: .global) ?? .zero,
                isTransitionActive: context.coordinator.isTransitionActive
              ) else { return }
        context.coordinator.didRequestDismiss = true
        onDismiss()
    }

    private func configure(_ coordinator: Coordinator) {
        coordinator.excludedFrames = excludedFrames
        coordinator.isTransitionActive = isTransitionActive
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let converter: CoordinateSpaceConverter
        var excludedFrames: [CGRect] = []
        var isTransitionActive = false
        var didRequestDismiss = false

        init(converter: CoordinateSpaceConverter) {
            self.converter = converter
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            didRequestDismiss = false
            let location = converter.location(in: .global)
            let translation = converter.translation(in: .global) ?? .zero
            // Decide from the touch origin, even if it has moved off a slider.
            let start = CGPoint(
                x: location.x - translation.x,
                y: location.y - translation.y
            )
            return PlayerFreeAreaDismissalPolicy.canBegin(
                at: start,
                velocity: converter.velocity(in: .global) ?? .zero,
                excludedFrames: excludedFrames,
                isTransitionActive: isTransitionActive
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            var touchedView = touch.view
            while let view = touchedView {
                if view is UIControl { return false }
                if let scrollView = view as? UIScrollView,
                   scrollView.isScrollEnabled,
                   scrollView.contentSize.height > scrollView.bounds.height + 1 {
                    return false
                }
                touchedView = view.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Keep the system's interactive zoom/edge dismissal in charge when
            // it recognizes the same swipe. The fallback never forces its end.
            true
        }
    }
}
