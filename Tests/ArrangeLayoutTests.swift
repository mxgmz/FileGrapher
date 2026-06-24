// Headless assert-harness for cartographer layout-switching (radial / grid / columns + auto-pick).
// Mirrors the pure slot geometry + `autoLayout` topology heuristic of the `extension AppModel` in
// MCPServer.swift the way the other Tests/*.swift do: port the logic over CoreGraphics, assert, run via
// `swift Tests/ArrangeLayoutTests.swift`. Standalone — NOT part of the SwiftPM target.
//
// Contract under test:
//  1. Grid: ⌈√n⌉ columns, row-major, centered under the hub, cells never overlap.
//  2. Columns: a single vertical stack on the hub's x, each cell below the last.
//  3. Radial: n slots equidistant from the hub, the first at 12 o'clock (straight above).
//  4. autoLayout: hub linked to most spokes → radial; a chain through the spokes → columns; else → grid.

import Foundation
import CoreGraphics

let gap: CGFloat = 80
func cellFor(_ reach: CGFloat) -> CGFloat { reach * 2 + gap }

// --- ported from AppModel.gridSlots ---
func gridSlots(hub: CGPoint, count: Int, hubReach: CGFloat, reach: CGFloat) -> [CGPoint] {
    let cell = cellFor(reach)
    let cols = max(1, Int(ceil(Double(count).squareRoot())))
    let firstY = hub.y + hubReach + gap + reach
    let startX = hub.x - CGFloat(cols - 1) * cell / 2
    return (0..<count).map { i in CGPoint(x: startX + CGFloat(i % cols) * cell, y: firstY + CGFloat(i / cols) * cell) }
}
// --- ported from AppModel.columnSlots ---
func columnSlots(hub: CGPoint, count: Int, hubReach: CGFloat, reach: CGFloat) -> [CGPoint] {
    let cell = cellFor(reach)
    let firstY = hub.y + hubReach + gap + reach
    return (0..<count).map { i in CGPoint(x: hub.x, y: firstY + CGFloat(i) * cell) }
}
// --- ported from AppModel.radialSlots ---
func radialSlots(hub: CGPoint, count: Int, hubReach: CGFloat, reach: CGFloat) -> [CGPoint] {
    let radius = max(hubReach + reach + gap, CGFloat(count) * (reach * 2 + gap) / (2 * .pi))
    return (0..<count).map { i in
        let angle = Double(i) / Double(count) * 2 * .pi - .pi / 2
        return CGPoint(x: hub.x + radius * CGFloat(cos(angle)), y: hub.y + radius * CGFloat(sin(angle)))
    }
}
// --- ported from AppModel.autoLayout ---
func autoLayout(hub: Int, spokes: [Int], edges: [(Int, Int)]) -> String {
    let spokeSet = Set(spokes)
    let linkedToHub = Set(edges.compactMap { e -> Int? in
        if e.0 == hub, spokeSet.contains(e.1) { return e.1 }
        if e.1 == hub, spokeSet.contains(e.0) { return e.0 }
        return nil
    })
    if linkedToHub.count >= max(2, (spokes.count + 1) / 2) { return "radial" }
    let interSpoke = edges.filter { spokeSet.contains($0.0) && spokeSet.contains($0.1) }.count
    if spokes.count >= 3, interSpoke >= spokes.count - 1 { return "columns" }
    return "grid"
}

var fails = 0
func check(_ name: String, _ pass: Bool) { print((pass ? "ok   " : "FAIL ") + name); if !pass { fails += 1 } }
func eq(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 1e-6) -> Bool { abs(a - b) < tol }

let hub = CGPoint(x: 100, y: 100)
let hubReach: CGFloat = 50, reach: CGFloat = 40
let cell = cellFor(reach)   // 160

// 1. GRID — n=4 → 2 cols × 2 rows, centered, non-overlapping.
let grid = gridSlots(hub: hub, count: 4, hubReach: hubReach, reach: reach)
check("grid: 4 slots", grid.count == 4)
check("grid: centered on hub.x (cols straddle it)", eq((grid[0].x + grid[1].x) / 2, hub.x))
check("grid: second row is one cell below the first", eq(grid[2].y - grid[0].y, cell))
let gridOK = (0..<grid.count).allSatisfy { i in
    (0..<grid.count).allSatisfy { j in i == j || hypot(grid[i].x - grid[j].x, grid[i].y - grid[j].y) >= cell - 1e-6 }
}
check("grid: no two cells overlap (centers ≥ one cell apart)", gridOK)

// 2. COLUMNS — n=3, single stack on hub.x, descending by a cell.
let col = columnSlots(hub: hub, count: 3, hubReach: hubReach, reach: reach)
check("columns: 3 slots", col.count == 3)
check("columns: all on the hub's x", col.allSatisfy { eq($0.x, hub.x) })
check("columns: each cell below the last", eq(col[1].y - col[0].y, cell) && eq(col[2].y - col[1].y, cell))

// 3. RADIAL — n=4, equidistant, first at 12 o'clock (straight above the hub, world y-down).
let rad = radialSlots(hub: hub, count: 4, hubReach: hubReach, reach: reach)
let radius = rad.map { hypot($0.x - hub.x, $0.y - hub.y) }
check("radial: 4 slots", rad.count == 4)
check("radial: all equidistant from the hub", radius.allSatisfy { eq($0, radius[0], 1e-4) })
check("radial: first slot is straight above the hub", eq(rad[0].x, hub.x, 1e-4) && rad[0].y < hub.y)

// 4. AUTO-PICK by topology.
check("auto: hub→most spokes ⇒ radial",
      autoLayout(hub: 0, spokes: [1, 2, 3, 4], edges: [(0, 1), (0, 2), (0, 3)]) == "radial")
check("auto: a chain through the spokes ⇒ columns",
      autoLayout(hub: 0, spokes: [1, 2, 3], edges: [(1, 2), (2, 3)]) == "columns")
check("auto: a flat unlinked set ⇒ grid",
      autoLayout(hub: 0, spokes: [1, 2, 3, 4], edges: []) == "grid")

print(fails == 0 ? "\nALL PASS" : "\n\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
