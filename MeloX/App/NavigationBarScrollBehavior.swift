import SwiftUI
import UIKit

/// Uses the navigation controller's native swipe behavior so the title and
/// profile actions leave the screen together, including in List-backed pages.
struct NavigationBarScrollBehavior: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.configureIfVisible()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restore(animated: false)
    }

    final class Controller: UIViewController {
        private weak var configuredNavigationController: UINavigationController?
        private var previousHidesBarsOnSwipe = false
        private var previousNavigationBarHidden = false
        private var isVisible = false

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isVisible = true
            configureIfVisible()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isVisible = false
            restore(animated: animated)
        }

        func configureIfVisible() {
            guard isVisible, let navigationController,
                  configuredNavigationController !== navigationController else {
                return
            }
            restore(animated: false)
            previousHidesBarsOnSwipe = navigationController.hidesBarsOnSwipe
            previousNavigationBarHidden = navigationController.isNavigationBarHidden
            configuredNavigationController = navigationController
            navigationController.hidesBarsOnSwipe = true
        }

        func restore(animated: Bool) {
            guard let navigationController = configuredNavigationController else { return }
            navigationController.hidesBarsOnSwipe = previousHidesBarsOnSwipe
            navigationController.setNavigationBarHidden(
                previousNavigationBarHidden,
                animated: animated
            )
            configuredNavigationController = nil
        }
    }
}
