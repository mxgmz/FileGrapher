import Foundation

/// The app-owned list of canvas-drawn wikilinks inside a markdown note, fenced by HTML-comment
/// markers so the app can rewrite it without ever touching the user's own prose. A connector on the
/// canvas *is* a `[[wikilink]]` in this block: draw an edge → a line appears here; delete it → the
/// line goes. Obsidian sees and clicks these links like any other.
///
/// Pure string transforms (no app state, Foundation only) so the read and write sides of the bridge
/// share one implementation and it stays trivially testable.
enum ManagedLinks {
    static let openMarker = "<!-- canvas-links -->"
    static let closeMarker = "<!-- /canvas-links -->"
    // The prose twin of the links block: an app-owned freeform region (summaries, folder-notes, MOCs)
    // the agent can write/rewrite without ever touching the user's own prose. Distinct markers so the
    // two managed blocks coexist in one note.
    static let noteOpenMarker = "<!-- canvas-note -->"
    static let noteCloseMarker = "<!-- /canvas-note -->"

    /// Wikilink targets listed in `text`'s managed block, in listed order (empty when there's no
    /// block). Only the managed block is read here; for every `[[link]]` in the prose use
    /// `wikilinkTargets(in:)`.
    static func targets(in text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        guard let block = blockRange(in: lines) else { return [] }
        return lines[block].compactMap(target(inLine:))
    }

    /// Every `[[wikilink]]` target anywhere in `text` (prose included), in document order, deduplicated
    /// — the read-side's view of a note's *intended* graph (vs. `targets`, which reads only the managed
    /// block). Alias/heading anchors are stripped, like `target(inLine:)`.
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

    /// `text` with its managed links block rewritten to list exactly `targets` (deduplicated, order
    /// preserved). Removes the block entirely when `targets` is empty. Content outside the markers
    /// is never altered. No-op (returns `text` unchanged) when there's nothing to add or remove.
    static func write(_ targets: [String], into text: String) -> String {
        setBlock(deduplicated(targets).map { "- [[\($0)]]" }, open: openMarker, close: closeMarker, in: text)
    }

    /// `text` with its app-managed *note* block rewritten to exactly `body` (split into lines). Removes
    /// the block when `body` is blank. The user's own prose outside the markers is never touched — this
    /// is the no-prose-clobber authoring path. No-op when nothing changes.
    static func writeNote(_ body: String, into text: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let inner = trimmed.isEmpty ? [] : trimmed.components(separatedBy: "\n")
        return setBlock(inner, open: noteOpenMarker, close: noteCloseMarker, in: text)
    }

    // MARK: Internals

    /// Rewrite the `open`…`close` fenced block in `text` to `inner` (markers re-added around it): replace
    /// it in place if present, append it otherwise, or remove it entirely when `inner` is empty. Lines
    /// outside the markers are never touched. The shared core under both `write` and `writeNote`.
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
        // Preserve the file's trailing newline (markdown convention) — the block machinery strips it
        // otherwise, churning the EOF on every write. User prose is unchanged either way; this just keeps
        // a write→clear round-trip byte-identical for files that ended in a newline.
        return text.hasSuffix("\n") && !result.hasSuffix("\n") ? result + "\n" : result
    }

    /// Inclusive line range of the `open`…`close` block, or nil if absent. Defaults to the links markers
    /// so `targets` reads the links block.
    private static func blockRange(in lines: [String], open: String = openMarker, close: String = closeMarker) -> ClosedRange<Int>? {
        guard let openIndex = lines.firstIndex(where: { $0.trimmed == open }),
              let closeOffset = lines[(openIndex + 1)...].firstIndex(where: { $0.trimmed == close })
        else { return nil }
        return openIndex...closeOffset
    }

    /// Parse the wikilink target from one list line (`- [[Target]] — note` → "Target"), or nil.
    private static func target(inLine line: String) -> String? {
        guard let open = line.range(of: "[["),
              let close = line.range(of: "]]", range: open.upperBound..<line.endIndex)
        else { return nil }
        return strip(String(line[open.upperBound..<close.lowerBound]))
    }

    /// A wikilink's inner text reduced to its target: an Obsidian alias or heading anchor is dropped
    /// (`Target|Alias` / `Target#Heading` → "Target"), then trimmed. Nil when nothing's left.
    private static func strip(_ inner: String) -> String? {
        var inner = inner
        if let bar = inner.firstIndex(of: "|") { inner = String(inner[..<bar]) }
        if let hash = inner.firstIndex(of: "#") { inner = String(inner[..<hash]) }
        let trimmed = inner.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func appendBlock(_ block: [String], to lines: inout [String]) {
        while lines.last == "" { lines.removeLast() }   // drop a trailing newline's empty line
        if !lines.isEmpty { lines.append("") }          // one blank line between prose and the block
        lines.append(contentsOf: block)
    }

    /// After removing the block, collapse the doubled/trailing blank line left at the seam.
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

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
