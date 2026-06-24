// Headless assert-harness for the title → preview → full display spectrum (Folder-Canvas Phase 3).
// Mirrors the two pure pieces the way the other Tests/*.swift do: the level state machine
// (AppModel.setPreview / setExpanded exclusivity in Model.swift) and the preview-line extraction
// (NodeView.previewLines in Canvas.swift). Port the logic, assert, run via
// `swift Tests/DisplayLevelTests.swift`. Standalone — NOT part of the SwiftPM target.
//
// Contract under test:
//  1. The three levels map from (expanded, preview): full > preview > title.
//  2. Preview and full are mutually exclusive — setting one clears the other (no box is ever both).
//  3. Toggling preview off returns to title; toggling full off returns to title.
//  4. previewLines = the first 6 NON-EMPTY, whitespace-trimmed lines, raw, newline-joined.

import Foundation

var fails = 0
func check(_ name: String, _ pass: Bool) { print((pass ? "ok   " : "FAIL ") + name); if !pass { fails += 1 } }

// --- ported from BoardNode.isExpanded/isPreviewing + setExpanded/setPreview (Model.swift) ---
enum Level: String { case title, preview, full }
struct Note {
    var expanded = false
    var preview = false
    var level: Level { expanded ? .full : (preview ? .preview : .title) }
    mutating func setExpanded(_ on: Bool) { expanded = on; if on { preview = false } }   // full clears preview
    mutating func setPreview(_ on: Bool)  { preview = on;  if on { expanded = false } }   // preview clears full
}

// 1 + 2 + 3: the state machine.
var n = Note()
check("default is title", n.level == .title)
n.setPreview(true)
check("setPreview(true) → preview", n.level == .preview)
check("preview is not also expanded", !n.expanded)
n.setExpanded(true)
check("setExpanded(true) from preview → full", n.level == .full)
check("full cleared preview (exclusive)", !n.preview)
n.setPreview(true)
check("setPreview(true) from full → preview", n.level == .preview)
check("preview cleared expanded (exclusive)", !n.expanded)
n.setPreview(false)
check("setPreview(false) → title", n.level == .title)
n.setExpanded(true); n.setExpanded(false)
check("setExpanded(false) → title", n.level == .title)

// --- ported from NodeView.previewLines (Canvas.swift) ---
func previewLines(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .prefix(6)
        .joined(separator: "\n")
}

check("skips blank lines + trims",
      previewLines("\n  # Title  \n\n  body line  \n") == "# Title\nbody line")
check("caps at 6 non-empty lines",
      previewLines((1...20).map { "line \($0)" }.joined(separator: "\n"))
        == (1...6).map { "line \($0)" }.joined(separator: "\n"))
check("empty / whitespace-only content → empty preview", previewLines("\n   \n\t\n").isEmpty)

print(fails == 0 ? "\nALL PASS" : "\n\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
