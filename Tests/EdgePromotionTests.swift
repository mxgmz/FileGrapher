// Headless assert-harness for edge promotion (SPEC-folder-canvas.md §4), the collapsed-folder
// architecture-graph view. Mirrors the pure logic of AppModel.promotedEdges (Model.swift) the way the
// push solver / ManagedLinks are tested: port the logic over lightweight structs, assert, run via `swift`.
// Standalone — not part of the SwiftPM target. Run it directly:  swift Tests/EdgePromotionTests.swift
//
// Contract verified here: a hidden endpoint promotes to its OUTERMOST collapsed ancestor (not a deeper
// one), links internal to one collapsed folder are dropped, parallel promoted links merge into one
// weighted connector, direction is preserved, and a board with nothing collapsed promotes nothing.

import Foundation

struct Node { let id: Int; let relPath: String; let kind: String; let collapsed: Bool
    var isCollapsedFolder: Bool { kind == "folder" && collapsed } }
struct Edge { let from: Int; let to: Int }
struct Promoted: Equatable { let from: Int; let to: Int; let weight: Int }

// --- ported from AppModel.promotedEdges ---
func promotedEdges(nodes: [Node], edges: [Edge]) -> [Promoted] {
    let collapsedFolders = nodes.filter { $0.isCollapsedFolder }.sorted { $0.relPath.count < $1.relPath.count }
    guard !collapsedFolders.isEmpty else { return [] }
    let byId = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    func representative(_ id: Int) -> Int? {
        guard let node = byId[id] else { return nil }
        return collapsedFolders.first { node.relPath.hasPrefix($0.relPath + "/") }?.id ?? id
    }
    var weights: [String: Promoted] = [:]
    var order: [String] = []
    for edge in edges {
        guard let from = representative(edge.from), let to = representative(edge.to),
              from != to, from != edge.from || to != edge.to else { continue }
        let key = "\(from)->\(to)"
        if let merged = weights[key] { weights[key] = Promoted(from: from, to: to, weight: merged.weight + 1) }
        else { weights[key] = Promoted(from: from, to: to, weight: 1); order.append(key) }
    }
    return order.map { weights[$0]! }
}

// --- fixture ---
//   A (root note)        X (root note)
//   F [collapsed] { B, C, G [collapsed] { D } }
//   H [collapsed] { E }
let A = 1, X = 2, F = 3, B = 4, C = 5, G = 6, D = 7, H = 8, E = 9
let nodes = [
    Node(id: A, relPath: "A.md",      kind: "note",   collapsed: false),
    Node(id: X, relPath: "X.md",      kind: "note",   collapsed: false),
    Node(id: F, relPath: "F",         kind: "folder", collapsed: true),
    Node(id: B, relPath: "F/B.md",    kind: "note",   collapsed: false),
    Node(id: C, relPath: "F/C.md",    kind: "note",   collapsed: false),
    Node(id: G, relPath: "F/G",       kind: "folder", collapsed: true),   // hidden (F collapsed above it)
    Node(id: D, relPath: "F/G/D.md",  kind: "note",   collapsed: false),
    Node(id: H, relPath: "H",         kind: "folder", collapsed: true),
    Node(id: E, relPath: "H/E.md",    kind: "note",   collapsed: false),
]
let edges = [
    Edge(from: A, to: B),   // A -> F          (B hidden in F)
    Edge(from: A, to: C),   // A -> F  (merges) -> A->F weight 2
    Edge(from: B, to: C),   // both -> F       (internal, dropped)
    Edge(from: B, to: E),   // F -> H          (B->F, E->H)
    Edge(from: D, to: E),   // F -> H  (merges) — D's OUTERMOST collapsed ancestor is F, not G -> F->H weight 2
    Edge(from: A, to: X),   // both visible    (real edge, not promoted)
]

var failures = 0
func check(_ name: String, _ pass: Bool) {
    print((pass ? "ok   " : "FAIL ") + name); if !pass { failures += 1 }
}

let result = promotedEdges(nodes: nodes, edges: edges)
func weight(_ from: Int, _ to: Int) -> Int? { result.first { $0.from == from && $0.to == to }?.weight }

check("A->F aggregates the two links into F (weight 2)", weight(A, F) == 2)
check("F->H aggregates B->E and D->E (weight 2)",         weight(F, H) == 2)
check("D promotes to OUTERMOST collapsed ancestor F, not G", weight(G, H) == nil)
check("B->C internal to F is dropped",                    !result.contains { Set([$0.from, $0.to]) == Set([B, C]) || $0.from == B || $0.to == C })
check("A->X (both visible) is NOT promoted",              weight(A, X) == nil)
check("direction preserved (A->F, not F->A)",             weight(F, A) == nil && weight(A, F) != nil)
check("exactly two promoted connectors",                  result.count == 2)
check("nothing collapsed -> nothing promoted",            promotedEdges(nodes: nodes.map { Node(id: $0.id, relPath: $0.relPath, kind: $0.kind, collapsed: false) }, edges: edges).isEmpty)

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
