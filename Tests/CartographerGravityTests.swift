// Headless assert-harness for the Sprint 30 Cartographer laws (VISION-agent-cartographer.md §4):
// GRAVITY (placeNearKin) and MINIMAL-MOTION (arrangeRadialMinimalMotion). Mirrors the pure geometry of
// the same-module `extension AppModel` in MCPServer.swift the way the other Tests/*.swift do: port the
// load-bearing logic over lightweight structs, assert, run via `swift Tests/CartographerGravityTests.swift`.
// Standalone — NOT part of the SwiftPM target (which is pinned to Sources/GraphingApp), so the app build
// never compiles it.
//
// Contract under test:
//  1. Minimal-motion: a spoke already within `arrangeSettleRadius` of its target slot is NOT moved; a spoke
//     far from its slot IS moved.
//  2. Gravity: placeNearKin picks a FREE slot adjacent to the anchor that does not overlap an occupied slot.

import Foundation
import CoreGraphics

let gridStep: CGFloat = 48
let arrangeSettleRadius: CGFloat = 24

// --- ported verbatim from AppModel.nearestFreeCenter (capped ring scan on the grid) ---
func nearestFreeCenter(box: CGRect, near desired: CGPoint, occupied: [CGRect]) -> CGPoint? {
    let center = CGPoint(x: box.midX, y: box.midY)
    func isFree(_ c: CGPoint) -> Bool {
        let probe = box.offsetBy(dx: c.x - center.x, dy: c.y - center.y)
        return !occupied.contains { $0.intersects(probe) }
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

// --- ported from AppModel.placeNearKin: seed one box-gap right of the anchor, ring-scan to the nearest gap ---
func placeNearKin(newBox: CGRect, anchor: CGRect, occupied: [CGRect]) -> CGPoint {
    let seed = CGPoint(x: anchor.maxX + gridStep + newBox.width / 2, y: anchor.midY)
    return nearestFreeCenter(box: newBox.offsetBy(dx: seed.x - newBox.midX, dy: seed.y - newBox.midY),
                             near: seed, occupied: occupied) ?? seed
}

// --- ported from AppModel.assignToNearestSlots: greedy nearest-slot pairing ---
func assignToNearestSlots(_ spokes: [Int], _ slots: [CGPoint], center: (Int) -> CGPoint) -> [(Int, CGPoint)] {
    var remaining = Array(slots.enumerated())
    var pairs: [(Int, CGPoint)] = []
    for spoke in spokes {
        let here = center(spoke)
        guard let pick = remaining.enumerated().min(by: {
            hypot($0.element.element.x - here.x, $0.element.element.y - here.y) <
            hypot($1.element.element.x - here.x, $1.element.element.y - here.y)
        }) else { continue }
        pairs.append((spoke, pick.element.element))
        remaining.remove(at: pick.offset)
    }
    return pairs
}

// --- ported from AppModel.arrangeRadialMinimalMotion: which spokes actually move (the skip-if-close guard) ---
// Returns the new center per spoke; a spoke left put keeps its original center.
func arrangeMinimalMotion(spokes: [Int], current: [Int: CGPoint], hub: CGPoint, radius: CGFloat) -> [Int: CGPoint] {
    let slots = (0..<spokes.count).map { i -> CGPoint in
        let angle = Double(i) / Double(spokes.count) * 2 * .pi - .pi / 2
        return CGPoint(x: hub.x + radius * CGFloat(cos(angle)), y: hub.y + radius * CGFloat(sin(angle)))
    }
    var result = current
    for (spoke, slot) in assignToNearestSlots(spokes, slots, center: { current[$0]! }) {
        let here = current[spoke]!
        if hypot(slot.x - here.x, slot.y - here.y) > arrangeSettleRadius { result[spoke] = slot }
    }
    return result
}

// --- harness ---
var failures = 0
func check(_ name: String, _ pass: Bool) { print((pass ? "ok   " : "FAIL ") + name); if !pass { failures += 1 } }
func eq(_ a: CGPoint, _ b: CGPoint, _ tol: CGFloat = 1e-6) -> Bool { hypot(a.x - b.x, a.y - b.y) < tol }

// === 1. MINIMAL-MOTION ===
// Hub at origin, radius 200, 4 spokes → slots at 12/3/6/9 o'clock: (0,-200),(200,0),(0,200),(-200,0).
// Spoke 0 starts ALREADY at its slot (must stay); spoke 1 starts ALREADY at its slot (must stay);
// spoke 2 starts within the settle radius of its slot (must stay); spoke 3 starts far away (must move).
let hub = CGPoint(x: 0, y: 0)
let radius: CGFloat = 200
let slot0 = CGPoint(x: 0, y: -200), slot1 = CGPoint(x: 200, y: 0)
let slot2 = CGPoint(x: 0, y: 200), slot3 = CGPoint(x: -200, y: 0)
let before: [Int: CGPoint] = [
    0: slot0,                                            // exactly on its slot
    1: slot1,                                            // exactly on its slot
    2: CGPoint(x: slot2.x + 10, y: slot2.y - 10),        // ~14 away (< 24 settle radius) → leave put
    3: CGPoint(x: 900, y: 900),                          // far → must move
]
let after = arrangeMinimalMotion(spokes: [0, 1, 2, 3], current: before, hub: hub, radius: radius)

check("minimal-motion: spoke already ON its slot is NOT moved",            eq(after[0]!, before[0]!))
check("minimal-motion: second on-slot spoke is NOT moved",                 eq(after[1]!, before[1]!))
check("minimal-motion: spoke within settle radius is NOT moved (exact)",   eq(after[2]!, before[2]!))
check("minimal-motion: far spoke IS moved",                                !eq(after[3]!, before[3]!))
check("minimal-motion: far spoke lands on a real radial slot",
      eq(after[3]!, slot0) || eq(after[3]!, slot1) || eq(after[3]!, slot2) || eq(after[3]!, slot3))

// Re-running on the just-arranged board is a no-op (the anti-twitch guarantee).
let afterAgain = arrangeMinimalMotion(spokes: [0, 1, 2, 3], current: after, hub: hub, radius: radius)
check("minimal-motion: re-arranging a tidy ring moves nothing",
      [0, 1, 2, 3].allSatisfy { eq(afterAgain[$0]!, after[$0]!) })

// === 2. GRAVITY (placeNearKin) ===
// Anchor (the kin) is a 160×100 note at the origin. The seed slot (one gap to its right) is OCCUPIED by an
// existing box, so gravity must skip to the next free slot — and the result must overlap NOTHING.
let noteSize = CGSize(width: 160, height: 100)
let anchor = CGRect(origin: CGPoint(x: -noteSize.width / 2, y: -noteSize.height / 2), size: noteSize)
let newBox = CGRect(origin: .zero, size: noteSize)

// seed center = one box-gap right of the anchor.
let seedCenter = CGPoint(x: anchor.maxX + gridStep + noteSize.width / 2, y: anchor.midY)
let blocker = CGRect(origin: CGPoint(x: seedCenter.x - noteSize.width / 2, y: seedCenter.y - noteSize.height / 2),
                     size: noteSize)
let occupied = [anchor, blocker]

let placed = placeNearKin(newBox: newBox, anchor: anchor, occupied: occupied)
let placedFrame = CGRect(origin: CGPoint(x: placed.x - noteSize.width / 2, y: placed.y - noteSize.height / 2),
                         size: noteSize)

check("gravity: placed slot does NOT overlap the anchor",  !placedFrame.intersects(anchor))
check("gravity: placed slot does NOT overlap the blocker", !placedFrame.intersects(blocker))
check("gravity: skipped the occupied seed (moved off it)", !eq(placed, seedCenter))
check("gravity: lands adjacent to the anchor (within ~2 box-widths)",
      hypot(placed.x - anchor.midX, placed.y - anchor.midY) < noteSize.width * 3)

// With the seed free, gravity takes it directly (closest-to-kin) — no needless detour.
let placedFree = placeNearKin(newBox: newBox, anchor: anchor, occupied: [anchor])
check("gravity: a free seed beside the anchor is taken as-is", eq(placedFree, seedCenter))

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
