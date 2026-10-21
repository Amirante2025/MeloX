#!/usr/bin/env python3
"""Check production swipe decisions using deterministic UIKit/converter stand-ins."""
import json
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
source = (REPO / "MeloX/Features/Player/NowPlaying/PlayerFreeAreaDismissal.swift").read_text()


def declaration(marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


production = declaration("enum PlayerFreeAreaDismissalPolicy") + "\n" + declaration(
    "final class Coordinator:"
)
stand_ins = r'''
import Foundation
import CoreGraphics
enum CoordinateSpace { case global }
final class CoordinateSpaceConverter {
    var point = CGPoint.zero
    var displacement = CGPoint.zero
    var speed = CGPoint(x: 0, y: 300)
    func location(in: CoordinateSpace) -> CGPoint { point }
    func translation(in: CoordinateSpace) -> CGPoint? { displacement }
    func velocity(in: CoordinateSpace) -> CGPoint? { speed }
}
protocol UIGestureRecognizerDelegate {}
class UIGestureRecognizer: NSObject {}
class UIView {
    var superview: UIView?
    var bounds = CGRect(x: 0, y: 0, width: 390, height: 300)
}
class UIControl: UIView {}
class UIScrollView: UIView {
    var isScrollEnabled = true
    var contentSize = CGSize(width: 390, height: 900)
}
class UITouch {
    let view: UIView?
    init(_ view: UIView?) { self.view = view }
}
'''
cases = r'''
@main
struct FreeAreaChecks {
    static func main() throws {
        var passed: [String] = []
        func check(_ description: String, _ value: Bool) {
            precondition(value, description)
            passed.append(description)
        }
        typealias Policy = PlayerFreeAreaDismissalPolicy
        let freePoint = CGPoint(x: 190, y: 200)
        let down = CGPoint(x: 10, y: 300)
        let control = CGRect(x: 40, y: 400, width: 310, height: 32)
        func begins(_ start: CGPoint, _ speed: CGPoint = down, active: Bool = false) -> Bool {
            Policy.canBegin(at: start, velocity: speed, excludedFrames: [control], isTransitionActive: active)
        }
        func ends(_ x: CGFloat, _ y: CGFloat, _ vx: CGFloat = 0, _ vy: CGFloat = 0, active: Bool = false) -> Bool {
            Policy.shouldDismiss(translation: CGPoint(x: x, y: y), velocity: CGPoint(x: vx, y: vy), isTransitionActive: active)
        }

        check("artwork accepts downward swipes", begins(freePoint))
        check("blank space between controls stays draggable", begins(CGPoint(x: 190, y: 460)))
        check("control touch origin is excluded", !begins(CGPoint(x: 190, y: 416)))
        check("control touch slop is excluded", !begins(CGPoint(x: 190, y: 398)))
        check("horizontal swipes do not begin", !begins(freePoint, CGPoint(x: 500, y: 80)))
        check("upward swipes do not begin", !begins(freePoint, CGPoint(x: 0, y: -500)))
        check("diagonal swipes do not begin", !begins(freePoint, CGPoint(x: 300, y: 320)))
        check("normal downward drag dismisses", ends(12, 100))
        check("short slow drag stays open", !ends(0, 35, 0, 100))
        check("short deliberate downward flick dismisses", ends(2, 30, 5, 900))
        check("tiny fast movement stays open", !ends(0, 12, 0, 1_000))
        check("horizontal release stays open", !ends(200, 100, 800, 100))
        check("upward release stays open", !ends(0, -100, 0, -800))
        check("reversing upward cancels a long drag", !ends(0, 120, 0, -500))
        check("native dismissal blocks a duplicate start", !begins(freePoint, active: true))
        check("native dismissal or cancellation is not forced to finish", !ends(0, 200, 0, 1_000, active: true))
        check("nonfinite touch origin is rejected", !begins(CGPoint(x: CGFloat.nan, y: 200)))
        check("nonfinite gesture values are rejected", !ends(0, 100, 0, .infinity))

        let converter = CoordinateSpaceConverter()
        let delegate = Coordinator(converter: converter)
        let pan = UIGestureRecognizer()
        converter.point = CGPoint(x: 190, y: 520)
        converter.displacement = CGPoint(x: 0, y: 104)
        delegate.excludedFrames = [control]
        check("dragging off a slider still checks the original touch", !delegate.gestureRecognizerShouldBegin(pan))
        converter.point = CGPoint(x: 190, y: 300)
        converter.displacement = CGPoint(x: 0, y: 100)
        check("free touch origin accepts movement into another region", delegate.gestureRecognizerShouldBegin(pan))
        delegate.isTransitionActive = true
        check("delegate observes active native transition", !delegate.gestureRecognizerShouldBegin(pan))
        delegate.isTransitionActive = false

        let button = UIControl()
        let buttonLabel = UIView()
        buttonLabel.superview = button
        check("UIKit control descendants retain their touches", !delegate.gestureRecognizer(pan, shouldReceive: UITouch(buttonLabel)))
        let list = UIScrollView()
        let listCell = UIView()
        listCell.superview = list
        check("scrollable lyrics and queues retain scrolling", !delegate.gestureRecognizer(pan, shouldReceive: UITouch(listCell)))
        list.contentSize.height = 200
        check("a non-scrolling tablet artwork column remains draggable", delegate.gestureRecognizer(pan, shouldReceive: UITouch(listCell)))
        list.contentSize.height = 900
        list.isScrollEnabled = false
        check("disabled scrolling does not block the free area", delegate.gestureRecognizer(pan, shouldReceive: UITouch(listCell)))
        check("ordinary artwork and blank views accept touches", delegate.gestureRecognizer(pan, shouldReceive: UITouch(UIView())))
        check("system interactive dismissal may recognize simultaneously", delegate.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: UIGestureRecognizer()))

        print(String(data: try JSONEncoder().encode(passed), encoding: .utf8)!)
    }
}
'''

with tempfile.TemporaryDirectory(prefix="melox-free-area-") as temporary:
    directory = Path(temporary)
    swift = directory / "FreeAreaChecks.swift"
    swift.write_text(stand_ins + production + cases)
    binary = directory / "checks"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
        "-parse-as-library", "-module-cache-path", str(directory / "modules"),
        str(swift), "-o", str(binary)
    ], check=True)
    result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
    passed = json.loads(result.stdout)
    print(json.dumps({
        "checksPassed": len(passed), "checks": passed,
        "scope": "Production swipe policy and delegate compiled with deterministic UIKit/converter stand-ins; gesture decisions only, no actual iOS touch delivery, volume rendering or zoom animation.",
        "uiBehaviorVerifiedOnDevice": False,
        "simulatorScreenshotsGenerated": False
    }, ensure_ascii=False))
