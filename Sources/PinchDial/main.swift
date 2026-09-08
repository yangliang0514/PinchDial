import AppKit
import PinchDialCore

// A local conversion check only: no event tap, event posting, UI, or permission request.
if CommandLine.arguments.contains("--check-gesture-encoding") {
    let backend = GestureBackend()
    let cases: [(GesturePhase, NSEvent.Phase, Double)] = [
        (.began, .began, 0), (.changed, .changed, 0.015),
        (.changed, .changed, -0.015), (.ended, .ended, 0), (.cancelled, .cancelled, 0)
    ]
    var failures = 0
    for (phase, expectedPhase, magnitude) in cases {
        guard let cg = backend.makeEvent(GestureSample(phase, magnitude), location: CGPoint(x: 200, y: 200)),
              let ns = NSEvent(cgEvent: cg) else {
            print("FAIL: \(phase) could not be converted to NSEvent")
            failures += 1
            continue
        }
        let valid = ns.type == .magnify && ns.phase == expectedPhase
            && abs(ns.magnification - magnitude) < 0.000001
        print("\(valid ? "PASS" : "FAIL"): \(phase), AppKit type=\(ns.type.rawValue), phase=\(ns.phase.rawValue), magnitude=\(ns.magnification)")
        if !valid { failures += 1 }
    }
    print("Local encoding check only; no events were posted and app compatibility is unverified.")
    exit(failures == 0 ? 0 : 1)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
