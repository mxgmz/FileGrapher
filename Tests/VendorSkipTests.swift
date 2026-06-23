// Headless assert-harness for the syncFromDisk vendor-dir skip-list (Epic A · Cartographer cleanup).
// Mirrors the pure membership predicate of AppModel.isVendorDir / vendorDirNames (Model.swift) the way
// PushSolverTests mirrors the collision solver: copy the relevant pure logic, assert, run via `swift`.
// Standalone — NOT part of the SwiftPM target (pinned to Sources/GraphingApp), so the app build never
// compiles it. Run it directly:  swift Tests/VendorSkipTests.swift
//
// Contract under test: opening a code repo as a vault must not box dependency/build dirs (one observed
// case spawned ~145 node_modules boxes). The set is matched by exact directory name; real content dirs
// (src, notes, "My Folder") must never be mistaken for vendor noise.

import Foundation

// --- ported verbatim from AppModel.vendorDirNames / isVendorDir ---
let vendorDirNames: Set<String> = [
    "node_modules", ".build", "dist", "build", "vendor", "Pods",
    ".next", "target", "__pycache__", ".venv", "venv",
]
func isVendorDir(_ name: String) -> Bool { vendorDirNames.contains(name) }

// --- asserts ---
var failures = 0
func check(_ cond: Bool, _ name: String) {
    print((cond ? "ok   " : "FAIL ") + name)
    if !cond { failures += 1 }
}

// 1. Every listed vendor/build dir is skipped.
for name in ["node_modules", ".build", "dist", "build", "vendor", "Pods", ".next", "target", "__pycache__", ".venv", "venv"] {
    check(isVendorDir(name), "vendor dir is skipped: \(name)")
}

// 2. Real content directories are NOT skipped (this is the regression that matters).
for name in ["src", "notes", "My Folder", "Sources", "docs", "Projects", "node_modules_backup", "buildings"] {
    check(!isVendorDir(name), "content dir is kept: \(name)")
}

// 3. Match is exact + case-sensitive: a differently-cased name is not treated as vendor noise.
check(!isVendorDir("Node_Modules"), "case-sensitive: Node_Modules is not vendor")
check(!isVendorDir("NODE_MODULES"), "case-sensitive: NODE_MODULES is not vendor")
check(!isVendorDir(""), "empty name is not vendor")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
