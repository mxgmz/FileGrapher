// Headless test for the authoring write path. Standalone (NOT in the SwiftPM target):
//     swift Tests/AuthoringTests.swift
// Ports ManagedLinks.setBlock / write / writeNote verbatim from Links.swift. Covers the no-prose-clobber
// law (writeNote never touches user prose), idempotent re-write, clear-on-empty, AND that the note block
// and the links block coexist independently (the regression net for the shared-core refactor).
import Foundation

private extension String { var trimmed: String { trimmingCharacters(in: .whitespaces) } }

enum ManagedLinks {
    static let openMarker = "<!-- canvas-links -->"
    static let closeMarker = "<!-- /canvas-links -->"
    static let noteOpenMarker = "<!-- canvas-note -->"
    static let noteCloseMarker = "<!-- /canvas-note -->"

    static func write(_ targets: [String], into text: String) -> String {
        setBlock(deduplicated(targets).map { "- [[\($0)]]" }, open: openMarker, close: closeMarker, in: text)
    }
    static func writeNote(_ body: String, into text: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let inner = trimmed.isEmpty ? [] : trimmed.components(separatedBy: "\n")
        return setBlock(inner, open: noteOpenMarker, close: noteCloseMarker, in: text)
    }
    private static func setBlock(_ inner: [String], open: String, close: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let existing = blockRange(in: lines, open: open, close: close)
        if inner.isEmpty {
            guard let existing else { return text }
            lines.removeSubrange(existing)
            trimBlankSeam(&lines, at: existing.lowerBound)
        } else {
            let block = [open] + inner + [close]
            if let existing { lines.replaceSubrange(existing, with: block) }
            else { appendBlock(block, to: &lines) }
        }
        let result = lines.joined(separator: "\n")
        return text.hasSuffix("\n") && !result.hasSuffix("\n") ? result + "\n" : result
    }
    private static func blockRange(in lines: [String], open: String = openMarker, close: String = closeMarker) -> ClosedRange<Int>? {
        guard let openIndex = lines.firstIndex(where: { $0.trimmed == open }),
              let closeOffset = lines[(openIndex + 1)...].firstIndex(where: { $0.trimmed == close })
        else { return nil }
        return openIndex...closeOffset
    }
    private static func appendBlock(_ block: [String], to lines: inout [String]) {
        while lines.last == "" { lines.removeLast() }
        if !lines.isEmpty { lines.append("") }
        lines.append(contentsOf: block)
    }
    private static func trimBlankSeam(_ lines: inout [String], at index: Int) {
        if index > 0, index == lines.count, lines.last == "" {
            lines.removeLast()
        } else if index > 0, index < lines.count, lines[index - 1] == "", lines[index] == "" {
            lines.remove(at: index)
        }
    }
    private static func deduplicated(_ targets: [String]) -> [String] {
        var seen = Set<String>()
        return targets.filter { seen.insert($0).inserted }
    }
}

var fails = 0
func check(_ cond: Bool, _ msg: String) { print((cond ? "ok   " : "FAIL ") + msg); if !cond { fails += 1 } }

// writeNote into empty text → block with body, nothing else
let intoEmpty = ManagedLinks.writeNote("Summary line.", into: "")
check(intoEmpty == "<!-- canvas-note -->\nSummary line.\n<!-- /canvas-note -->",
      "writeNote: into empty text produces just the fenced block")

// user prose is never clobbered — it's preserved verbatim, block appended after a blank seam
let prose = "# My note\n\nUser's own paragraph."
let withNote = ManagedLinks.writeNote("Agent summary.", into: prose)
check(withNote.hasPrefix(prose) && withNote.contains("<!-- canvas-note -->\nAgent summary.\n<!-- /canvas-note -->"),
      "writeNote: user prose preserved verbatim, block appended")

// idempotent re-write: running again with new body replaces the block (no duplicate markers)
let rewritten = ManagedLinks.writeNote("Updated summary.", into: withNote)
check(rewritten.components(separatedBy: "<!-- canvas-note -->").count == 2
        && rewritten.contains("Updated summary.") && !rewritten.contains("Agent summary."),
      "writeNote: re-run replaces the block in place (idempotent, no duplication)")
check(rewritten.hasPrefix(prose), "writeNote: prose still intact after re-write")

// clear on empty/blank body removes the block, prose intact
check(ManagedLinks.writeNote("", into: rewritten) == prose,
      "writeNote: empty body removes the block, restoring exactly the user prose")
check(ManagedLinks.writeNote("\n  \n", into: withNote) == prose,
      "writeNote: whitespace/newline-only body counts as blank → removes the block")

// multi-line / multi-paragraph body round-trips
let multi = ManagedLinks.writeNote("## Map\n\n- [[A]]\n- [[B]]", into: "")
check(multi == "<!-- canvas-note -->\n## Map\n\n- [[A]]\n- [[B]]\n<!-- /canvas-note -->",
      "writeNote: multi-line body preserved between the markers")

// COEXISTENCE: a note block and a links block live together, each edited without disturbing the other
let withLinks = ManagedLinks.write(["Alpha", "Beta"], into: prose)
let both = ManagedLinks.writeNote("Synthesis.", into: withLinks)
check(both.contains("<!-- canvas-links -->\n- [[Alpha]]\n- [[Beta]]\n<!-- /canvas-links -->")
        && both.contains("<!-- canvas-note -->\nSynthesis.\n<!-- /canvas-note -->"),
      "coexist: writeNote leaves the links block untouched")
let bothAfterRelink = ManagedLinks.write(["Alpha", "Beta", "Gamma"], into: both)
check(bothAfterRelink.contains("- [[Gamma]]") && bothAfterRelink.contains("<!-- canvas-note -->\nSynthesis.\n<!-- /canvas-note -->"),
      "coexist: write(links) leaves the note block untouched")

// trailing newline preserved: a write→clear round-trip on a file that ended in "\n" is byte-identical
let withEOF = "# Doc\n\nA paragraph.\n"
check(ManagedLinks.writeNote("", into: ManagedLinks.writeNote("Note.", into: withEOF)) == withEOF,
      "writeNote: write→clear round-trip is byte-identical, EOF newline preserved")
check(ManagedLinks.writeNote("Note.", into: withEOF).hasSuffix("<!-- /canvas-note -->\n"),
      "writeNote: a file's trailing newline survives the write")

// regression net for the refactor: write() empty-targets still removes the links block
check(ManagedLinks.write([], into: withLinks) == prose,
      "write: empty targets removes the links block (refactor preserved old behavior)")
check(ManagedLinks.write(["Alpha", "Alpha", "Beta"], into: "").contains("- [[Alpha]]\n- [[Beta]]"),
      "write: dedupes targets (refactor preserved old behavior)")

print(fails == 0 ? "\nALL PASS" : "\n\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
