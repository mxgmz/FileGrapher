// Headless test for the perception read path. Standalone (NOT in the SwiftPM target): run with
//     swift Tests/PerceptionTests.swift
// Ports the two non-trivial pure bits of canvas_read — prose wikilink extraction and the per-note
// content cap — verbatim from Links.swift / MCPServer.readJSON. Scoping rides canvas_get's coverage.
import Foundation

// ---- ported from Links.swift: ManagedLinks.wikilinkTargets / strip / deduplicated ----
enum ManagedLinks {
    static func wikilinkTargets(in text: String) -> [String] {
        var found: [String] = []
        var cursor = text.startIndex
        while let open = text.range(of: "[[", range: cursor..<text.endIndex),
              let close = text.range(of: "]]", range: open.upperBound..<text.endIndex) {
            if let target = strip(String(text[open.upperBound..<close.lowerBound])) { found.append(target) }
            cursor = close.upperBound
        }
        return deduplicated(found)
    }
    private static func strip(_ inner: String) -> String? {
        var inner = inner
        if let bar = inner.firstIndex(of: "|") { inner = String(inner[..<bar]) }
        if let hash = inner.firstIndex(of: "#") { inner = String(inner[..<hash]) }
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private static func deduplicated(_ targets: [String]) -> [String] {
        var seen = Set<String>()
        return targets.filter { seen.insert($0).inserted }
    }
}

// ---- ported from MCPServer.readJSON: the per-note content cap ----
func capped(_ full: String, maxChars: Int) -> (text: String, chars: Int, truncated: Bool) {
    let truncated = full.count > maxChars
    return (truncated ? String(full.prefix(maxChars)) : full, full.count, truncated)
}

// ---- harness ----
var fails = 0
func check(_ cond: Bool, _ msg: String) {
    print((cond ? "ok   " : "FAIL ") + msg); if !cond { fails += 1 }
}

// wikilinkTargets: prose + alias + heading + dedupe + ignore-non-links
let prose = """
See [[Alpha]] and [[Beta|the beta]] for context.
Also [[Gamma#Section]], and [[Alpha]] again (dup).
A bare [bracket] and [[   ]] (empty) are not links.
"""
check(ManagedLinks.wikilinkTargets(in: prose) == ["Alpha", "Beta", "Gamma"],
      "wikilinkTargets: prose/alias/heading parsed, deduped, empties+non-links ignored")
check(ManagedLinks.wikilinkTargets(in: "no links here") == [],
      "wikilinkTargets: returns empty when there are none")
check(ManagedLinks.wikilinkTargets(in: "[[A]][[B]]") == ["A", "B"],
      "wikilinkTargets: adjacent links both found")

// content cap: under, exactly at, and over maxChars
let short = capped("hello", maxChars: 10)
check(short.text == "hello" && short.chars == 5 && !short.truncated,
      "cap: short text passes through, not truncated")

let exact = capped(String(repeating: "x", count: 10), maxChars: 10)
check(exact.text.count == 10 && exact.chars == 10 && !exact.truncated,
      "cap: text exactly at the cap is not flagged truncated")

let over = capped(String(repeating: "x", count: 50), maxChars: 10)
check(over.text.count == 10 && over.chars == 50 && over.truncated,
      "cap: over-cap text is cut to maxChars, chars reports the full length, truncated=true")

// links survive the cap (extracted from full text, not the capped excerpt)
let longWithLink = String(repeating: "x", count: 100) + " [[Tail]]"
let body = capped(longWithLink, maxChars: 10)
check(body.truncated && ManagedLinks.wikilinkTargets(in: longWithLink) == ["Tail"],
      "cap+links: a link past the cap still appears (links parse the full text)")

print(fails == 0 ? "\nALL PASS" : "\n\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
