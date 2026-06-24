// Headless assert-harness for the gardening diagnostic (AppModel.boardHealth in MCPServer.swift).
// Mirrors the four pure structural signals the way the other Tests/*.swift do: port the logic over
// lightweight structs, assert, run via `swift Tests/BoardHealthTests.swift`. Standalone — NOT part of
// the SwiftPM target.
//
// Contract under test:
//  1. orphans = notes with no connector (folders are never orphans).
//  2. crowdedFolders = folders with more than `crowdedFolderLimit` direct children.
//  3. overlaps = VISIBLE sibling boxes (same parent) whose frames intersect — not cross-parent pairs.
//  4. unbackedConnectors = note↔note edges not backed by a real [[link]] (linkBacked == false).

import Foundation
import CoreGraphics

let crowdedFolderLimit = 12

struct Node { var id: Int; var kind: String; var parent: String; var relPath: String; var frame: CGRect }
struct Edge { var from: Int; var to: Int; var linkBacked: Bool }

func orphans(_ nodes: [Node], _ edges: [Edge]) -> [Int] {
    let linked = Set(edges.flatMap { [$0.from, $0.to] })
    return nodes.filter { $0.kind == "note" && !linked.contains($0.id) }.map(\.id)
}
func crowdedFolders(_ nodes: [Node]) -> [Int] {
    nodes.filter { $0.kind == "folder" }
        .filter { folder in nodes.filter { $0.parent == folder.relPath }.count > crowdedFolderLimit }
        .map(\.id)
}
func overlaps(_ nodes: [Node]) -> [(Int, Int)] {
    var out: [(Int, Int)] = []
    for (_, sibs) in Dictionary(grouping: nodes, by: { $0.parent }) where sibs.count > 1 {
        for i in 0..<sibs.count {
            for j in (i + 1)..<sibs.count where sibs[i].frame.intersects(sibs[j].frame) {
                out.append((sibs[i].id, sibs[j].id))
            }
        }
    }
    return out
}
func unbacked(_ nodes: [Node], _ edges: [Edge]) -> [(Int, Int)] {
    let noteIds = Set(nodes.filter { $0.kind == "note" }.map(\.id))
    return edges.filter { !$0.linkBacked && noteIds.contains($0.from) && noteIds.contains($0.to) }.map { ($0.from, $0.to) }
}

var fails = 0
func check(_ name: String, _ pass: Bool) { print((pass ? "ok   " : "FAIL ") + name); if !pass { fails += 1 } }

func box(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x, y: y, width: 100, height: 60) }

// 1. orphans — note 3 has no edge; folder 9 is never an orphan even with no edge.
let nodes1 = [
    Node(id: 1, kind: "note", parent: "", relPath: "a.md", frame: box(0, 0)),
    Node(id: 2, kind: "note", parent: "", relPath: "b.md", frame: box(400, 0)),
    Node(id: 3, kind: "note", parent: "", relPath: "c.md", frame: box(800, 0)),
    Node(id: 9, kind: "folder", parent: "", relPath: "F", frame: box(0, 400)),
]
let edges1 = [Edge(from: 1, to: 2, linkBacked: true)]
check("orphan = the unconnected note", Set(orphans(nodes1, edges1)) == [3])
check("a folder with no edge is NOT an orphan", !orphans(nodes1, edges1).contains(9))

// 2. crowded folders — F has 13 children (> limit), G has 12 (== limit, not crowded).
var nodes2: [Node] = [
    Node(id: 100, kind: "folder", parent: "", relPath: "F", frame: box(0, 0)),
    Node(id: 200, kind: "folder", parent: "", relPath: "G", frame: box(0, 0)),
]
for i in 0..<13 { nodes2.append(Node(id: 1000 + i, kind: "note", parent: "F", relPath: "F/n\(i).md", frame: box(0, 0))) }
for i in 0..<12 { nodes2.append(Node(id: 2000 + i, kind: "note", parent: "G", relPath: "G/n\(i).md", frame: box(0, 0))) }
check("folder past the limit is crowded", crowdedFolders(nodes2).contains(100))
check("folder exactly at the limit is not crowded", !crowdedFolders(nodes2).contains(200))

// 3. overlaps — siblings 1&2 overlap; sibling 3 is clear; cross-parent 1&4 overlapping in space is NOT flagged.
let nodes3 = [
    Node(id: 1, kind: "note", parent: "", relPath: "a.md", frame: box(0, 0)),
    Node(id: 2, kind: "note", parent: "", relPath: "b.md", frame: box(50, 30)),    // overlaps 1
    Node(id: 3, kind: "note", parent: "", relPath: "c.md", frame: box(900, 900)),  // clear
    Node(id: 4, kind: "note", parent: "Other", relPath: "Other/d.md", frame: box(10, 10)), // overlaps 1 in space, different parent
]
let ov = overlaps(nodes3).map { Set([$0.0, $0.1]) }
check("overlapping siblings are flagged", ov.contains(Set([1, 2])))
check("clear sibling is not flagged", !ov.contains(where: { $0.contains(3) }))
check("cross-parent boxes are NOT flagged as overlaps", !ov.contains(Set([1, 4])))

// 4. unbacked connectors — note↔note non-linkBacked flagged; linkBacked not; note↔folder not.
let nodes4 = [
    Node(id: 1, kind: "note", parent: "", relPath: "a.md", frame: box(0, 0)),
    Node(id: 2, kind: "note", parent: "", relPath: "b.md", frame: box(400, 0)),
    Node(id: 3, kind: "folder", parent: "", relPath: "F", frame: box(800, 0)),
]
let edges4 = [
    Edge(from: 1, to: 2, linkBacked: false),  // visual-only note↔note → flagged
    Edge(from: 2, to: 1, linkBacked: true),   // real link → not flagged
    Edge(from: 1, to: 3, linkBacked: false),  // note↔folder → not flagged (only note↔note counts)
]
let ub = unbacked(nodes4, edges4)
check("visual-only note↔note connector is flagged", ub.contains(where: { $0 == (1, 2) }))
check("link-backed connector is not flagged", !ub.contains(where: { $0 == (2, 1) }))
check("note↔folder connector is not counted", !ub.contains(where: { $0 == (1, 3) }))

print(fails == 0 ? "\nALL PASS" : "\n\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
