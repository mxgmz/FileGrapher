// Headless assert-harness for the Quick-open palette (⌘P) matcher (Sprint 30 · Lane A).
// Mirrors the pure ranking logic of AppModel.quickOpenMatches (QuickOpen.swift) the way the other
// Tests/*.swift do: port the logic over lightweight structs, assert, run via
// `swift Tests/QuickOpenSearchTests.swift`. Standalone — not part of the SwiftPM target.
//
// Contract under test:
//  1. Case-insensitive substring match (query "no" matches "Notes", "INBOX").
//  2. Exact-prefix matches rank ABOVE mid-string substrings.
//  3. Empty query returns ALL nodes (capped) — opening the palette previews the board.
//  4. No match returns empty.
//  5. The result count is capped at `quickOpenLimit`.

import Foundation

let quickOpenLimit = 20

struct Node { var name: String; var kind: String }

// Ported from AppModel.quickOpenMatches: substring filter, prefix-first ranking, alpha tiebreak, cap.
func quickOpenMatches(_ query: String, in nodes: [Node]) -> [Node] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !needle.isEmpty else {
        return Array(nodes.sorted { $0.name.lowercased() < $1.name.lowercased() }.prefix(quickOpenLimit))
    }
    let ranked = nodes.compactMap { node -> (Node, Bool)? in
        let name = node.name.lowercased()
        guard name.contains(needle) else { return nil }
        return (node, name.hasPrefix(needle))
    }
    let sorted = ranked.sorted { lhs, rhs in
        if lhs.1 != rhs.1 { return lhs.1 }
        return lhs.0.name.lowercased() < rhs.0.name.lowercased()
    }
    return Array(sorted.map { $0.0 }.prefix(quickOpenLimit))
}

var failures = 0
func check(_ name: String, _ pass: Bool) { print((pass ? "ok   " : "FAIL ") + name); if !pass { failures += 1 } }

let nodes = [
    Node(name: "Inbox",        kind: "folder"),
    Node(name: "Notes",        kind: "folder"),
    Node(name: "Project Note", kind: "note"),   // mid-string "note"
    Node(name: "noteworthy",   kind: "note"),    // prefix "note"
    Node(name: "Daily",        kind: "note"),
]

// 1: case-insensitive substring — "IN" matches Inbox (prefix) and "noteworthy"? no — only Inbox here.
let inMatches = quickOpenMatches("IN", in: nodes).map { $0.name }
check("case-insensitive substring: 'IN' matches Inbox", inMatches.contains("Inbox"))
check("case-insensitive substring: 'IN' is case-insensitive (lowercased input matches too)",
      quickOpenMatches("in", in: nodes).map { $0.name } == inMatches)

// 2: exact-prefix ranks ABOVE mid-string. "note" → noteworthy (prefix) before "Project Note" (mid),
//    and before "Notes" — wait, "Notes" is also a prefix of "note"? No: "notes".hasPrefix("note") is true.
//    So prefixes are noteworthy + Notes (alpha: "notes" < "noteworthy"), then mid "Project Note".
let noteMatches = quickOpenMatches("note", in: nodes).map { $0.name }
check("exact-prefix ranks above mid-string substring",
      noteMatches == ["Notes", "noteworthy", "Project Note"])
check("a prefix match precedes any mid-string match",
      noteMatches.firstIndex(of: "noteworthy")! < noteMatches.firstIndex(of: "Project Note")!)

// 3: empty (and whitespace-only) query returns ALL nodes, alphabetized.
check("empty query returns all nodes", quickOpenMatches("", in: nodes).count == nodes.count)
check("whitespace-only query returns all nodes", quickOpenMatches("   ", in: nodes).count == nodes.count)

// 4: no match → empty.
check("no-match returns empty", quickOpenMatches("zzzzz", in: nodes).isEmpty)

// 5: result count capped at quickOpenLimit.
let many = (0..<50).map { Node(name: "match\($0)", kind: "note") }
check("result count capped at quickOpenLimit", quickOpenMatches("match", in: many).count == quickOpenLimit)
check("empty query also capped at quickOpenLimit", quickOpenMatches("", in: many).count == quickOpenLimit)

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
