// Headless assert-harness for the Folder-Canvas Phase 2 folder-as-card seed migration (board.json v2→v3).
// Mirrors the pure logic of AppModel.seedFolderCardsIfNeeded / legacyAutoGrownFrame / worldCenter
// (Model.swift) the way the other Tests/*.swift do: port the logic over lightweight structs, assert,
// run via `swift Tests/FolderCardSeedTests.swift`. Standalone — not part of the SwiftPM target.
//
// Contract under test (what the PR description requires the test to prove):
//  1. The seed is INVISIBLE — nothing's RENDERED position moves. For a LEAF note that means worldCenter
//     is unchanged; for a FOLDER it means its rendered footprint is unchanged, which is assertion 2.
//  2. Each folder's POST-seed worldFrame (its new world center + new size) == its pre-seed auto-grown
//     frame `grown[F]` — so the card covers exactly what the folder used to display.
//  3. The version guard works: a board already at v3 is left untouched.
//
// NOTE on "every node's worldCenter unchanged" (PR text): that holds for LEAF nodes only. A folder's
// worldCenter intentionally MOVES onto grown[F].center (off-center, by construction of this fixture) so
// its stored card covers the old auto-grown footprint — that IS the seed. "Nothing visually moves"
// therefore means: leaves keep their world center (assertion 1), folders keep their rendered footprint
// (assertion 2). The two cannot both be a *world-center* invariant for a folder once grown[F] is
// off-center, which is exactly why the fixture is asymmetric. Reviewer: focus here.

import Foundation

struct Node {
    var id: Int
    var relPath: String
    var kind: String   // "note" | "folder"
    var x: Double      // center, RELATIVE to parent folder's center (root: relative to origin)
    var y: Double
    var width: Double
    var height: Double
    var collapsed: Bool = false
    var parentRel: String { (relPath as NSString).deletingLastPathComponent }
}

let folderPadding = 18.0
let folderHeaderHeight = 40.0
let collapsedFolderWidth = 220.0

func parentFolder(of node: Node, in nodes: [Node]) -> Node? {
    let parent = node.parentRel
    return parent.isEmpty ? nil : nodes.first { $0.kind == "folder" && $0.relPath == parent }
}

func directChildren(of relPath: String, in nodes: [Node]) -> [Node] {
    nodes.filter { $0.parentRel == relPath }
}

// up-walk, summing relative centers to the root (ported from AppModel.worldCenter)
func worldCenter(of node: Node, in nodes: [Node]) -> (x: Double, y: Double) {
    var x = node.x, y = node.y
    var current = node, depth = 0
    var seen = Set([node.relPath])
    while let parent = parentFolder(of: current, in: nodes) {
        guard depth < 256, seen.insert(parent.relPath).inserted else { break }
        x += parent.x; y += parent.y; current = parent; depth += 1
    }
    return (x, y)
}

func worldFrame(of node: Node, in nodes: [Node]) -> (minX: Double, minY: Double, width: Double, height: Double) {
    let c = worldCenter(of: node, in: nodes)
    return (c.x - node.width / 2, c.y - node.height / 2, node.width, node.height)
}

// union of two world frames (minX/minY/width/height)
func union(_ a: (minX: Double, minY: Double, width: Double, height: Double),
          _ b: (minX: Double, minY: Double, width: Double, height: Double))
    -> (minX: Double, minY: Double, width: Double, height: Double) {
    let minX = min(a.minX, b.minX), minY = min(a.minY, b.minY)
    let maxX = max(a.minX + a.width, b.minX + b.width)
    let maxY = max(a.minY + a.height, b.minY + b.height)
    return (minX, minY, maxX - minX, maxY - minY)
}

// ported from AppModel.legacyAutoGrownFrame — the OLD auto-grow footprint (no outlier filter in this
// fixture: every child is near its siblings, so autoGrowChildren == all children).
func legacyAutoGrownFrame(of node: Node, in nodes: [Node]) -> (minX: Double, minY: Double, width: Double, height: Double) {
    guard node.kind == "folder" else { return worldFrame(of: node, in: nodes) }
    if node.collapsed {
        let wf = worldFrame(of: node, in: nodes)
        return (wf.minX, wf.minY, min(wf.width, collapsedFolderWidth), folderHeaderHeight)
    }
    var frame = worldFrame(of: node, in: nodes)
    let children = directChildren(of: node.relPath, in: nodes)
    if let first = children.first {
        var bounds = legacyAutoGrownFrame(of: first, in: nodes)
        for child in children.dropFirst() { bounds = union(bounds, legacyAutoGrownFrame(of: child, in: nodes)) }
        let needed = (minX: bounds.minX - folderPadding,
                      minY: bounds.minY - folderPadding - folderHeaderHeight,
                      width: bounds.width + 2 * folderPadding,
                      height: bounds.height + 2 * folderPadding + folderHeaderHeight)
        frame = union(frame, needed)
    }
    return frame
}

// ported from AppModel.seedFolderCardsIfNeeded — snapshot first, then move each folder's world center
// onto its auto-grown frame's center and counter-shift its direct children. Iterate by id and RE-READ
// the live node each pass (a folder may already have been counter-shifted by its parent's seed, so
// worldCenter must read the current board, never a stale pre-loop copy — this is the subtle bit).
func seedFolderCards(_ nodes: inout [Node]) {
    let folderIDs = nodes.filter { $0.kind == "folder" }.map { $0.id }
    let grown = Dictionary(uniqueKeysWithValues:
        nodes.filter { $0.kind == "folder" }.map { ($0.id, legacyAutoGrownFrame(of: $0, in: nodes)) })
    for id in folderIDs {
        guard let index = nodes.firstIndex(where: { $0.id == id }), let target = grown[id] else { continue }
        let folder = nodes[index]
        let worldBefore = worldCenter(of: folder, in: nodes)
        let dx = (target.minX + target.width / 2) - worldBefore.x
        let dy = (target.minY + target.height / 2) - worldBefore.y
        nodes[index].width = target.width; nodes[index].height = target.height
        nodes[index].x += dx; nodes[index].y += dy
        for child in directChildren(of: folder.relPath, in: nodes) {
            guard let childIndex = nodes.firstIndex(where: { $0.id == child.id }) else { continue }
            nodes[childIndex].x -= dx; nodes[childIndex].y -= dy
        }
    }
}

// 2-level-nested fixture (already v2 / relative coords). Children placed ASYMMETRICALLY so the
// auto-grown frame is genuinely off-center from each folder's stored center.
//   root F  (folder) at world (1000,1000), small stored frame
//     note B1, note B2  (both inside F, pushed to one side)
//     subfolder G       (inside F, off to a corner)
//       note D1, note D2 (inside G, pushed to one side — depth 2)
var nodes = [
    Node(id: 1, relPath: "F",          kind: "folder", x: 1000, y: 1000, width: 200, height: 140),
    Node(id: 2, relPath: "F/B1.md",    kind: "note",   x:  300, y:   80, width: 180, height: 110),  // rel to F
    Node(id: 3, relPath: "F/B2.md",    kind: "note",   x:  520, y:  240, width: 180, height: 110),  // rel to F
    Node(id: 4, relPath: "F/G",        kind: "folder", x:  600, y:  500, width: 200, height: 140),  // rel to F
    Node(id: 5, relPath: "F/G/D1.md",  kind: "note",   x:  160, y:   40, width: 160, height: 100),  // rel to G
    Node(id: 6, relPath: "F/G/D2.md",  kind: "note",   x:  340, y:  220, width: 160, height: 100),  // rel to G
]

var failures = 0
func check(_ name: String, _ pass: Bool) { print((pass ? "ok   " : "FAIL ") + name); if !pass { failures += 1 } }
func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
func eqPoint(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Bool { close(a.x, b.x) && close(a.y, b.y) }

// Snapshot the PRE-seed truth: every node's world center, and every folder's auto-grown footprint.
let worldBefore = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, worldCenter(of: $0, in: nodes)) })
let grownBefore = Dictionary(uniqueKeysWithValues:
    nodes.filter { $0.kind == "folder" }.map { ($0.id, legacyAutoGrownFrame(of: $0, in: nodes)) })

// Sanity: the fixture's auto-grown frames really are off-center (otherwise the test proves nothing).
for folder in nodes where folder.kind == "folder" {
    let g = grownBefore[folder.id]!
    let stored = worldBefore[folder.id]!
    check("fixture: \(folder.relPath) auto-grown frame is OFF-center from its stored center",
          abs((g.minX + g.width / 2) - stored.x) > 1 || abs((g.minY + g.height / 2) - stored.y) > 1)
}

seedFolderCards(&nodes)

// 1: the seed is invisible — every LEAF note's world center is unchanged, at every nesting depth
// (depth-1 B1/B2 inside F, depth-2 D1/D2 inside G). This proves children don't drift when their
// ancestor folders re-center onto their cards.
for node in nodes where node.kind == "note" {
    check("worldCenter(\(node.relPath)) unchanged after seed",
          eqPoint(worldCenter(of: node, in: nodes), worldBefore[node.id]!))
}

// 2: each folder's post-seed worldFrame == its pre-seed auto-grown frame — including the depth-2-parent
// subfolder G. This is the folder's "rendered footprint unchanged", and it composes correctly only when
// the seed re-reads each folder's live (already counter-shifted) center, not a stale snapshot.
for node in nodes where node.kind == "folder" {
    let wf = worldFrame(of: node, in: nodes)
    let g = grownBefore[node.id]!
    check("worldFrame(\(node.relPath)) == grown[\(node.relPath)] after seed",
          close(wf.minX, g.minX) && close(wf.minY, g.minY) && close(wf.width, g.width) && close(wf.height, g.height))
}

// 3: idempotency — the seed is a FIXED POINT. Re-running it on the already-seeded board moves nothing:
// each folder's card already equals its children's auto-grown union + padding, so the recomputed
// footprint is the card itself and delta == 0 for every node. (The real code also has a version >= 3
// guard that returns early; this proves the underlying math is safe even if that guard were absent.)
var reseeded = nodes
seedFolderCards(&reseeded)
let unchanged = zip(nodes.sorted { $0.id < $1.id }, reseeded.sorted { $0.id < $1.id }).allSatisfy {
    close($0.x, $1.x) && close($0.y, $1.y) && close($0.width, $1.width) && close($0.height, $1.height)
}
check("re-seeding the already-seeded board changes nothing (seed is a fixed point)", unchanged)

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
