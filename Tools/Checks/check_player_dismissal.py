#!/usr/bin/env python3
"""Exercise production dismissal callbacks with deterministic UIKit stand-ins."""
import json
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
observer = (REPO / "MeloX/App/PlayerDismissalTransitionObserver.swift").read_text()
controller = observer[observer.index("final class PlayerDismissalObserverController:"):]
content = (REPO / "MeloX/App/ContentView.swift").read_text()
start = content.index("    private func updatePlayerDismissalProtection(")
opening = content.index("{", start)
depth = 1
end = opening + 1
while depth:
    depth += (content[end] == "{") - (content[end] == "}")
    end += 1
update = content[start:end]

stand_ins = r'''
import Foundation

enum MockColor { case clear }
class UIView {
    var backgroundColor: MockColor?
    var isUserInteractionEnabled = true
    var accessibilityElementsHidden = false
}
struct MockTransitionContext { let isCancelled: Bool }
class MockTransitionCoordinator {
    var acceptsCompletion = true
    var registrations = 0
    var completion: ((MockTransitionContext) -> Void)?
    func animate(
        alongsideTransition: ((MockTransitionContext) -> Void)?,
        completion: ((MockTransitionContext) -> Void)?
    ) -> Bool {
        registrations += 1
        if acceptsCompletion { self.completion = completion }
        return acceptsCompletion
    }
    func complete(cancelled: Bool = false) {
        completion?(MockTransitionContext(isCancelled: cancelled))
    }
}
class UIViewController {
    var parent: UIViewController?
    var isBeingDismissed = false
    var transitionCoordinator: MockTransitionCoordinator?
    var view: UIView!
    init(nibName: String?, bundle: Bundle?) {}
    required init?(coder: NSCoder) {}
    func loadView() {}
    func viewWillDisappear(_ animated: Bool) {}
    func viewDidDisappear(_ animated: Bool) {}
    func viewDidAppear(_ animated: Bool) {}
}
'''
fixture = '''
final class RootFixture {
    var activePlayerDismissalID: UUID?
    var events: [(UUID, Bool)] = []
    func receive(_ id: UUID, _ active: Bool) {
        events.append((id, active))
        updatePlayerDismissalProtection(id: id, isActive: active)
    }
''' + update + "\n}\n"

cases = r'''
@main
struct DismissalChecks {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
    }
    static func make(
        root: RootFixture, coordinator: MockTransitionCoordinator? = nil
    ) -> PlayerDismissalObserverController {
        let observer = PlayerDismissalObserverController(onTransitionChange: root.receive)
        observer.transitionCoordinator = coordinator
        return observer
    }
    static func main() throws {
        var passed: [String] = []

        do {
            let root = RootFixture()
            let observer = make(root: root)
            observer.viewDidAppear(true)
            require(root.activePlayerDismissalID == nil, "No protection while simply displaying the player")
            passed.append("player presentation and steady display remain unprotected")
        }
        do {
            let root = RootFixture()
            let transition = MockTransitionCoordinator()
            let observer = make(root: root, coordinator: transition)
            observer.isBeingDismissed = true
            observer.viewWillDisappear(true)
            require(root.activePlayerDismissalID != nil, "Native dismissal must begin protection")
            observer.viewDidDisappear(true)
            require(root.activePlayerDismissalID != nil, "Appearance removal must not beat registered native completion")
            transition.complete()
            require(root.activePlayerDismissalID == nil, "Native completion must immediately release")
            passed.append("completed dismissal ends at coordinator completion")
        }
        do {
            let root = RootFixture()
            let transition = MockTransitionCoordinator()
            let observer = make(root: root, coordinator: transition)
            observer.isBeingDismissed = true
            observer.viewWillDisappear(true)
            observer.isBeingDismissed = false
            observer.viewDidAppear(true)
            require(root.activePlayerDismissalID != nil, "Wait for native cancellation settlement")
            transition.complete(cancelled: true)
            require(root.activePlayerDismissalID == nil, "Cancelled return must release")
            let retry = MockTransitionCoordinator()
            observer.transitionCoordinator = retry
            observer.isBeingDismissed = true
            observer.viewWillDisappear(true)
            require(root.activePlayerDismissalID != nil, "A new gesture after cancellation must start protection")
            retry.complete()
            require(root.activePlayerDismissalID == nil, "The retried gesture must release")
            passed.append("cancelled interactive dismissal releases after native settlement and can retry")
        }
        do {
            let root = RootFixture()
            let transition = MockTransitionCoordinator()
            let observer = make(root: root, coordinator: transition)
            observer.viewWillDisappear(true)
            observer.viewDidDisappear(true)
            observer.viewDidAppear(true)
            require(root.events.isEmpty && transition.registrations == 0, "A covering sheet must not start protection")
            passed.append("share-sheet coverage does not count as player dismissal")
        }
        do {
            let root = RootFixture()
            let transition = MockTransitionCoordinator()
            let ancestor = UIViewController(nibName: nil, bundle: nil)
            ancestor.isBeingDismissed = true
            let parent = UIViewController(nibName: nil, bundle: nil)
            parent.parent = ancestor
            let observer = make(root: root, coordinator: transition)
            observer.parent = parent
            observer.viewWillDisappear(true)
            require(root.activePlayerDismissalID != nil, "Find the dismissing presentation ancestor")
            transition.complete()
            require(root.activePlayerDismissalID == nil, "Ancestor transition completion releases")
            passed.append("dismissal of an ancestor starts protection")
        }
        do {
            let root = RootFixture()
            let transition = MockTransitionCoordinator()
            let observer = make(root: root, coordinator: transition)
            observer.isBeingDismissed = true
            observer.viewWillDisappear(true)
            observer.viewWillDisappear(true)
            require(root.events.count == 1 && transition.registrations == 1, "Duplicate appearance callback must not duplicate the transition")
            transition.complete()
            passed.append("duplicate disappearance notification is idempotent")
        }
        do {
            let root = RootFixture()
            let transition = MockTransitionCoordinator()
            var observer: PlayerDismissalObserverController? = make(root: root, coordinator: transition)
            weak let weakObserver = observer
            observer!.isBeingDismissed = true
            observer!.viewWillDisappear(true)
            observer!.detach()
            observer = nil
            require(weakObserver == nil, "Completion must not retain the observer")
            require(root.activePlayerDismissalID != nil, "Dismantling must not release a registered animation early")
            transition.complete()
            require(root.activePlayerDismissalID == nil, "Completion must release after observer deallocation")
            passed.append("SwiftUI dismantling does not end registered protection early")
        }
        do {
            let root = RootFixture()
            let oldTransition = MockTransitionCoordinator()
            let newTransition = MockTransitionCoordinator()
            let old = make(root: root, coordinator: oldTransition)
            let new = make(root: root, coordinator: newTransition)
            old.isBeingDismissed = true
            new.isBeingDismissed = true
            old.viewWillDisappear(true)
            new.viewWillDisappear(true)
            let newestID = root.activePlayerDismissalID
            oldTransition.complete(cancelled: true)
            require(root.activePlayerDismissalID == newestID, "Stale completion must not release a newer return")
            newTransition.complete()
            require(root.activePlayerDismissalID == nil, "Current completion releases")
            passed.append("stale completion cannot release a newer dismissal")
        }
        for cancelled in [false, true] {
            let root = RootFixture()
            let observer = make(root: root)
            observer.isBeingDismissed = true
            observer.viewWillDisappear(false)
            require(root.activePlayerDismissalID != nil, "Uncoordinated dismissal starts protection")
            if cancelled { observer.viewDidAppear(false) }
            else { observer.viewDidDisappear(false) }
            require(root.activePlayerDismissalID == nil, "Uncoordinated appearance fallback must release")
            passed.append(cancelled ? "no-coordinator cancellation fallback" : "nonanimated dismissal fallback")
        }
        do {
            let root = RootFixture()
            let transition = MockTransitionCoordinator()
            transition.acceptsCompletion = false
            let observer = make(root: root, coordinator: transition)
            observer.isBeingDismissed = true
            observer.viewWillDisappear(true)
            observer.viewDidDisappear(true)
            require(root.activePlayerDismissalID == nil, "Rejected completion registration needs appearance fallback")
            passed.append("rejected coordinator registration falls back to native appearance completion")
        }
        do {
            let root = RootFixture()
            let observer = make(root: root)
            observer.isBeingDismissed = true
            observer.viewWillDisappear(false)
            observer.detach()
            require(root.activePlayerDismissalID == nil, "Uncoordinated dismantling must not leave a stale guard")
            passed.append("uncoordinated dismantling cleans up protection")
        }
        print(String(data: try JSONEncoder().encode(passed), encoding: .utf8)!)
    }
}
'''
with tempfile.TemporaryDirectory(prefix="melox-dismissal-") as tmp:
    temporary = Path(tmp)
    source = temporary / "DismissalChecks.swift"
    source.write_text(stand_ins + controller + fixture + cases)
    binary = temporary / "checks"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
        "-parse-as-library", "-module-cache-path", str(temporary / "modules"),
        str(source), "-o", str(binary)
    ], check=True)
    result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
    passed = json.loads(result.stdout)
    print(json.dumps({
        "checksPassed": len(passed), "checks": passed,
        "scope": "Production observer controller and root callback compiled with deterministic UIKit stand-ins; callback ordering only, no actual iOS gestures or rendering.",
        "uiBehaviorVerifiedOnDevice": False,
        "simulatorScreenshotsGenerated": False
    }, ensure_ascii=False))

