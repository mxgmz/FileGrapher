// Headless assert-harness for the Folder-Canvas Phase 2 folder-as-card SCROLL CLAMP (PR-2). Mirrors the
// pure math of AppModel.clampScroll (Model.swift): port the one clamp function, assert, run via
// `swift Tests/FolderScrollClampTests.swift`. Standalone — not part of the SwiftPM target.
//
// Contract under test (what the PR description requires the test to prove):
//  - content TALLER than the card → can scroll down to reveal the bottom, but not past it (offset bottoms
//    out at interior − content, a negative value);
//  - content that FITS → offset pinned at 0 (nothing to reveal);
//  - the two axes clamp INDEPENDENTLY (overflow on one axis doesn't unlock the other);
//  - a delta past the limit SATURATES at the limit (never overshoots in either direction).
//
// The render/scroll/hit-test wiring itself is NOT headless-testable — the orchestrator visually verifies
// it. This file pins only the clamp, which is the single piece of pure logic in `scrolledFolder`.

import Foundation

// Ported verbatim from AppModel.clampScroll. Per axis: an axis whose content fits the interior pins at 0;
// otherwise the offset is bounded to [interior − content … 0] (0 == top/left, interior − content == flush
// against the bottom/right edge).
func clampScroll(_ offset: CGSize, interior: CGSize, content: CGSize) -> CGSize {
    func axis(_ value: CGFloat, _ visible: CGFloat, _ extent: CGFloat) -> CGFloat {
        extent <= visible ? 0 : min(0, max(visible - extent, value))
    }
    return CGSize(width: axis(offset.width, interior.width, content.width),
                  height: axis(offset.height, interior.height, content.height))
}

var failures = 0
func check(_ name: String, _ pass: Bool) { print((pass ? "ok   " : "FAIL ") + name); if !pass { failures += 1 } }
func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1e-6 }
func eq(_ a: CGSize, _ b: CGSize) -> Bool { close(a.width, b.width) && close(a.height, b.height) }

// A card 400x300 showing content 400x1000: only the vertical axis overflows (limit = 300 − 1000 = −700).
let interior = CGSize(width: 400, height: 300)
let tallContent = CGSize(width: 400, height: 1000)

// 1. A downward scroll within range reveals lower content (negative offset), not clamped yet.
check("scroll down within range is kept",
      eq(clampScroll(CGSize(width: 0, height: -200), interior: interior, content: tallContent),
         CGSize(width: 0, height: -200)))

// 2. Scrolling down PAST the bottom saturates at interior − content (−700), never past.
check("scroll past the bottom saturates at the limit (−700)",
      eq(clampScroll(CGSize(width: 0, height: -5000), interior: interior, content: tallContent),
         CGSize(width: 0, height: -700)))

// 3. Bottom-flush exactly: the limit value passes through unchanged.
check("bottom-flush offset (−700) passes through",
      eq(clampScroll(CGSize(width: 0, height: -700), interior: interior, content: tallContent),
         CGSize(width: 0, height: -700)))

// 4. Scrolling UP past the top (positive offset) pins at 0 — you can't pull content below its top edge.
check("scroll up past the top pins at 0",
      eq(clampScroll(CGSize(width: 0, height: 250), interior: interior, content: tallContent),
         CGSize(width: 0, height: 0)))

// 5. Content that FITS both axes → offset pinned at 0 regardless of the requested delta.
let fits = CGSize(width: 300, height: 200)
check("content that fits pins at 0 (both axes)",
      eq(clampScroll(CGSize(width: -500, height: -500), interior: interior, content: fits),
         CGSize(width: 0, height: 0)))

// 6. Axes clamp INDEPENDENTLY: content overflows ONLY horizontally → the y axis stays pinned at 0 even
//    when a vertical delta is requested, and the x axis clamps to its own limit (400 − 900 = −500).
let wideContent = CGSize(width: 900, height: 200)   // overflows x only (200 < 300)
check("independent axes: x clamps to −500, y pinned at 0 (content fits vertically)",
      eq(clampScroll(CGSize(width: -5000, height: -5000), interior: interior, content: wideContent),
         CGSize(width: -500, height: 0)))

// 7. Both axes overflow → each saturates at its OWN limit independently.
let bigContent = CGSize(width: 700, height: 1000)   // x limit −300, y limit −700
check("both axes overflow → each saturates at its own limit",
      eq(clampScroll(CGSize(width: -9999, height: -9999), interior: interior, content: bigContent),
         CGSize(width: -300, height: -700)))

// 8. A negative delta on a fits-axis combined with overflow on the other: the fits-axis still pins at 0.
check("mixed: x overflows (kept −100), y fits (pinned 0)",
      eq(clampScroll(CGSize(width: -100, height: -100), interior: interior, content: wideContent),
         CGSize(width: -100, height: 0)))

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
