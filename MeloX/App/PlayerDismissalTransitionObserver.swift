import SwiftUI
import UIKit

/// Observe the cover's native dismissal, including edge and downward swipes.
struct PlayerDismissalTransitionObserver: UIViewControllerRepresentable {
    let onTransitionChange: (UUID, Bool) -> Void

    func makeUIViewController(context: Context) -> PlayerDismissalObserverController {
        PlayerDismissalObserverController(onTransitionChange: onTransitionChange)
    }

    func updateUIViewController(
        _ controller: PlayerDismissalObserverController,
        context: Context
    ) {
        controller.onTransitionChange = onTransitionChange
    }

    static func dismantleUIViewController(
        _ controller: PlayerDismissalObserverController,
        coordinator: ()
    ) {
        controller.detach()
    }
}

final class PlayerDismissalObserverController: UIViewController {
    var onTransitionChange: (UUID, Bool) -> Void

    private var activeTransitionID: UUID?
    private var hasCoordinatorCompletion = false

    init(onTransitionChange: @escaping (UUID, Bool) -> Void) {
        self.onTransitionChange = onTransitionChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Being covered by a share sheet is not a dismissal of this player.
        guard isDismissingPlayer, activeTransitionID == nil else { return }

        let id = UUID()
        activeTransitionID = id
        hasCoordinatorCompletion = false
        onTransitionChange(id, true)

        if let transitionCoordinator {
            let notify = onTransitionChange
            let registered = transitionCoordinator.animate(
                alongsideTransition: nil
            ) { [weak self] _ in
                // This also runs after a cancelled gesture has settled back.
                // Keep this callback alive if SwiftUI dismantles the probe early.
                notify(id, false)
                if self?.activeTransitionID == id {
                    self?.activeTransitionID = nil
                    self?.hasCoordinatorCompletion = false
                }
            }
            if activeTransitionID == id {
                hasCoordinatorCompletion = registered
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        finishWithoutCoordinator()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        finishWithoutCoordinator()
    }

    func detach() {
        finishWithoutCoordinator()
    }

    private var isDismissingPlayer: Bool {
        var controller: UIViewController? = self
        while let candidate = controller {
            if candidate.isBeingDismissed { return true }
            controller = candidate.parent
        }
        return false
    }

    private func finishWithoutCoordinator() {
        guard !hasCoordinatorCompletion, let id = activeTransitionID else { return }
        activeTransitionID = nil
        onTransitionChange(id, false)
    }
}
