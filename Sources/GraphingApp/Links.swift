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

    /// Wikilink targets listed in `text`'s managed block, in listed order (empty when there's no
    /// block). Only the managed block is read here; prose wikilinks elsewhere are the read-side's job.
    static func targets(in text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        guard let block = blockRange(in: lines) else { return [] }
        return lines[block].compactMap(target(inLine:))
    }

    /// `text` with its managed block rewritten to list exactly `targets` (deduplicated, order
    /// preserved). Removes the block entirely when `targets` is empty. Content outside the markers
    /// is never altered. No-op (returns `text` unchanged) when there's nothing to add or remove.
    static func write(_ targets: [String], into text: String) -> String {
        let wanted = deduplicated(targets)
        var lines = text.components(separatedBy: "\n")
        let existing = blockRange(in: lines)

        if wanted.isEmpty {
            guard let existing else { return text }
            lines.removeSubrange(existing)
            trimBlankSeam(&lines, at: existing.lowerBound)
            return lines.joined(separator: "\n")
        }

        let block = render(wanted)
        if let existing {
            lines.replaceSubrange(existing, with: block)
        } else {
            appendBlock(block, to: &lines)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Internals

    /// Inclusive line range of the managed block (open marker … close marker), or nil if absent.
    private static func blockRange(in lines: [String]) -> ClosedRange<Int>? {
        guard let open = lines.firstIndex(where: { $0.trimmed == openMarker }),
              let close = lines[(open + 1)...].firstIndex(where: { $0.trimmed == closeMarker })
        else { return nil }
        return open...close
    }

    /// Parse the wikilink target from one list line (`- [[Target]] — note` → "Target"), or nil.
    private static func target(inLine line: String) -> String? {
        guard let open = line.range(of: "[["),
              let close = line.range(of: "]]", range: open.upperBound..<line.endIndex)
        else { return nil }
        var inner = String(line[open.upperBound..<close.lowerBound])
        // Strip an Obsidian alias or heading anchor: [[Target|Alias]] / [[Target#Heading]].
        if let bar = inner.firstIndex(of: "|") { inner = String(inner[..<bar]) }
        if let hash = inner.firstIndex(of: "#") { inner = String(inner[..<hash]) }
        let trimmed = inner.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func render(_ targets: [String]) -> [String] {
        [openMarker] + targets.map { "- [[\($0)]]" } + [closeMarker]
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
