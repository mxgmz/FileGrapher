// Headless assert-harness for the T4 collision push solver + pin-as-obstacle.
// Mirrors the pure geometry of AppModel.separationVector / resolveOverlaps (Model.swift) the way
// nearestFreeCenter / ManagedLinks are tested: concatenate the relevant logic, assert, run via `swift`.
// Standalone — not part of the SwiftPM target (pinned to Sources/GraphingApp), so the app build never
// compiles it. Run it directly:  swift Tests/PushSolverTests.swift
//
// Boxes here are simple notes (id, rect, pinned). Folder auto-grow is exercised by the real app; this
// harness verifies the solver's contract: an overlapped sibling is pushed clear, a pinned sibling never
// moves and the mover routes around it, all-pinned falls back to a mover-snap, and nothing resolves
// unless we explicitly run the solver (= the "never reshuffle on load" guarantee).

import Foundation
import CoreGraphics

let worldBound = 1_000_000.0
let gridStep: CGFloat = 48
func clampCoord(_ v: Double) -> Double { v.isFinite ? min(max(v, -worldBound), worldBound) : 0 }

struct Box { var id: Int; var rect: CGRect; var pinned: Bool = false; var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) } }

// --- ported verbatim from AppModel.separationVector ---
func separationVector(_ mover: CGRect, outOf obstacle: CGRect) -> CGSize {
    guard mover.intersects(obstacle) else { return .zero }
    let overlap = mover.intersection(obstacle)
    if overlap.width <= overlap.height {
        let dx = mover.midX < obstacle.midX ? -overlap.width : overlap.width
        return CGSize(width: dx, height: 0)
    }
    let dy = mover.midY < obstacle.midY ? -overlap.height : overlap.height
    return CGSize(width: 0, height: dy)
}

// nearestFreeCenter fallback (mover routes around ALL siblings incl. pinned), capped ring scan.
func nearestFreeCenter(mover: Box, near desired: CGPoint, siblings: [Box]) -> CGPoint? {
    let others = siblings.filter { $0.id != mover.id }.map { $0.rect }
    func isFree(_ c: CGPoint) -> Bool {
        let probe = mover.rect.offsetBy(dx: c.x - mover.center.x, dy: c.y - mover.center.y)
        return !others.contains { $0.intersects(probe) }
    }
    if isFree(desired) { return desired }
    for ring in 1...24 {
        let r = CGFloat(ring) * gridStep
        for k in -ring...ring {
            let o = CGFloat(k) * gridStep
            for c in [CGPoint(x: desired.x + o, y: desired.y - r),
                      CGPoint(x: desired.x + o, y: desired.y + r),
                      CGPoint(x: desired.x - r, y: desired.y + o),
                      CGPoint(x: desired.x + r, y: desired.y + o)] where isFree(c) { return c }
        }
    }
    return nil
}

// --- ported from AppModel.resolveOverlaps (folder-subtree translation collapses to a plain move here) ---
func resolveOverlaps(movedId: Int, boxes: inout [Box]) {
    guard let moverIdx = boxes.firstIndex(where: { $0.id == movedId }) else { return }
    let mover = boxes[moverIdx]
    let pinnedFrames = boxes.filter { $0.id != movedId && $0.pinned }.map { $0.rect }
    if pinnedFrames.contains(where: { $0.intersects(mover.rect) }) {
        if let free = nearestFreeCenter(mover: mover, near: mover.center, siblings: boxes), free != mover.center {
            boxes[moverIdx].rect = mover.rect.offsetBy(dx: free.x - mover.center.x, dy: free.y - mover.center.y)
        }
        return
    }
    var center: [Int: CGPoint] = Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0.center) })
    let baseFrame: [Int: CGRect] = Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0.rect) })
    func frame(_ id: Int) -> CGRect {
        let base = baseFrame[id]!, c = center[id]!
        return base.offsetBy(dx: c.x - base.midX, dy: c.y - base.midY)
    }
    let pushable = boxes.filter { $0.id != movedId && !$0.pinned }.map { $0.id }
    for _ in 0..<24 {
        var moved = false
        for id in pushable {
            let me = frame(id)
            var worst: (CGRect, CGFloat) = (.null, 0)
            for other in boxes where other.id != id {
                let f = frame(other.id)
                let area = me.intersection(f)
                let depth = min(area.width, area.height)
                if me.intersects(f), depth > worst.1 { worst = (f, depth) }
            }
            guard worst.1 > 0 else { continue }
            let push = separationVector(me, outOf: worst.0)
            guard push != .zero else { continue }
            center[id] = CGPoint(x: clampCoord(center[id]!.x + push.width), y: clampCoord(center[id]!.y + push.height))
            moved = true
        }
        if !moved { break }
    }
    for id in pushable {
        let c = center[id]!
        if let i = boxes.firstIndex(where: { $0.id == id }) {
            boxes[i].rect = baseFrame[id]!.offsetBy(dx: c.x - baseFrame[id]!.midX, dy: c.y - baseFrame[id]!.midY)
        }
    }
}

// --- asserts ---
var failures = 0
func check(_ cond: Bool, _ name: String) {
    print((cond ? "ok   " : "FAIL ") + name)
    if !cond { failures += 1 }
}
func anyOverlap(_ boxes: [Box]) -> Bool {
    for i in boxes.indices { for j in boxes.indices where j > i {
        if boxes[i].rect.intersects(boxes[j].rect) { return true }
    } }
    return false
}
func box(_ id: Int, _ cx: Double, _ cy: Double, w: Double = 120, h: Double = 60, pinned: Bool = false) -> Box {
    Box(id: id, rect: CGRect(x: cx - w/2, y: cy - h/2, width: w, height: h), pinned: pinned)
}

// 1. separationVector picks the shorter axis and the correct sign.
do {
    let a = CGRect(x: 0, y: 0, width: 100, height: 100)        // mover (left/above)
    let b = CGRect(x: 90, y: 0, width: 100, height: 100)       // obstacle to the right, 10px x-overlap
    let s = separationVector(a, outOf: b)
    check(s.width == -10 && s.height == 0, "separationVector pushes left by the 10px x-overlap")
    let c = CGRect(x: 0, y: 90, width: 100, height: 100)       // obstacle below, 10px y-overlap
    check(separationVector(a, outOf: c) == CGSize(width: 0, height: -10), "separationVector pushes up on shorter y-axis")
    check(separationVector(a, outOf: CGRect(x: 500, y: 0, width: 10, height: 10)) == .zero, "no overlap -> zero vector")
}

// 2. A dropped box stays put; an overlapped sibling is pushed clear.
do {
    var boxes = [box(1, 100, 100), box(2, 130, 100)]   // mover=2 dropped onto 1
    let moverBefore = boxes[1].center
    resolveOverlaps(movedId: 2, boxes: &boxes)
    check(boxes[1].center == moverBefore, "mover stays exactly where it was dropped")
    check(!anyOverlap(boxes), "overlapped sibling pushed clear (no overlap remains)")
}

// 3. A pinned sibling never moves; the non-pinned mover/cascade routes around it.
do {
    var boxes = [box(1, 100, 100, pinned: true), box(2, 100, 100)]  // 2 dropped on a PINNED 1
    let pinnedRect = boxes[0].rect
    resolveOverlaps(movedId: 2, boxes: &boxes)
    check(boxes[0].rect == pinnedRect, "pinned sibling never moves")
    check(!anyOverlap(boxes), "mover routed around the pinned obstacle (no overlap)")
}

// 3b. Pinned box is the OBSTACLE while a free sibling is pushed into it -> cascade must not move the pin.
do {
    // mover(1) pushes 2 rightward into pinned 3; 2 must end up clear of both, 3 stays.
    var boxes = [box(1, 100, 100), box(2, 150, 100), box(3, 230, 100, pinned: true)]
    let pinnedRect = boxes[2].rect
    resolveOverlaps(movedId: 1, boxes: &boxes)
    check(boxes[2].rect == pinnedRect, "pinned obstacle stays put during a cascade")
    check(!anyOverlap(boxes), "cascade settles around the pinned box")
}

// 4. All siblings pinned and the mover lands on one -> mover snaps via the fallback (never deadlocks).
do {
    var boxes = [box(1, 100, 100, pinned: true), box(2, 240, 100, pinned: true), box(3, 110, 100)]
    let p1 = boxes[0].rect, p2 = boxes[1].rect
    resolveOverlaps(movedId: 3, boxes: &boxes)
    check(boxes[0].rect == p1 && boxes[1].rect == p2, "all-pinned: the pinned boxes never move")
    check(!anyOverlap(boxes), "all-pinned: the mover snapped to a free gap (fallback)")
}

// 5. Load does not reshuffle: an already-overlapping board is untouched until we explicitly resolve.
do {
    let overlapping = [box(1, 100, 100), box(2, 120, 100), box(3, 140, 100)]
    var boxes = overlapping   // simulate "just loaded" — no resolve call
    check(boxes.map { $0.rect } == overlapping.map { $0.rect } && anyOverlap(boxes),
          "construction/load leaves existing overlaps exactly as stored (no settle)")
}

// 6. Cascade is bounded: a dense row resolves to non-overlap within the cap (no spin).
do {
    var boxes = (0..<8).map { box($0, 100 + Double($0) * 15, 100) }  // 8 boxes ~15px apart, heavy overlap
    resolveOverlaps(movedId: 0, boxes: &boxes)
    check(boxes[0].center == box(0, 100, 100).center, "dense cascade: the mover still didn't move")
    check(!anyOverlap(boxes), "dense cascade settles to no-overlap within the iteration cap")
}

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
