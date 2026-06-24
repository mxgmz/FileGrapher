// Headless assert-harness for the Finder drag-in import (Sprint 30 · Lane B). Mirrors the pure pieces of
// AppModel.importFiles + Vault.uniqueRel (Model.swift) the way the other Tests/*.swift do: port the logic
// over Foundation only, assert, run via `swift Tests/FinderImportTests.swift`. Standalone — NOT part of
// the SwiftPM target.
//
// Contract verified here:
//   1. Collision-safe naming: importing a name that already exists yields a distinct "copy" name and
//      never clobbers the existing file (ported Vault.uniqueRel, exercised against a real temp dir).
//   2. Two imports of the same name don't collide (each gets its own free path).
//   3. Boxable-type filter: .md/.csv (and code) files are accepted; other file types are skipped;
//      a folder is always accepted (mirrors AppModel.importFiles' accept rule).

import Foundation

var fails = 0
func check(_ name: String, _ pass: Bool) { print((pass ? "ok   " : "FAIL ") + name); if !pass { fails += 1 } }

// --- ported from Vault.uniqueRel (Model.swift) ---
func uniqueRel(root: URL, dir: String, base: String, ext: String) -> String {
    func make(_ name: String) -> String {
        let comp = ext.isEmpty ? name : "\(name).\(ext)"
        return dir.isEmpty ? comp : "\(dir)/\(comp)"
    }
    func exists(_ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(rel).path)
    }
    if !exists(make(base)) { return make(base) }
    var i = 2
    while exists(make("\(base) \(i)")) { i += 1 }
    return make("\(base) \(i)")
}

// --- ported from AppModel.boxableExts + importFiles' accept rule (Model.swift / FinderImport.swift) ---
let gappCodeExts: Set<String> = [
    "swift", "json", "js", "jsx", "mjs", "cjs", "ts", "tsx", "py", "rb", "go", "rs",
    "java", "kt", "kts", "c", "h", "cpp", "hpp", "cc", "hh", "cs", "sh", "bash", "zsh",
    "fish", "yaml", "yml", "toml", "html", "htm", "css", "scss", "sass", "less", "xml",
    "sql", "php", "lua", "pl", "r", "jl", "m", "mm", "gradle", "ini", "conf", "cfg", "env"
]
let boxableExts: Set<String> = Set(["md", "markdown", "csv"]).union(gappCodeExts)
func accepts(ext: String, isDirectory: Bool) -> Bool {
    isDirectory || boxableExts.contains(ext.lowercased())
}

// --- a real temp vault, cleaned up at the end ---
let vault = FileManager.default.temporaryDirectory
    .appendingPathComponent("gapp-finder-import-tests-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: vault) }

func write(_ rel: String) {
    FileManager.default.createFile(atPath: vault.appendingPathComponent(rel).path, contents: Data())
}

// 1. Importing into the root with a name that already exists → a distinct "copy"-style free name, original untouched.
write("Notes.md")
let firstFree = uniqueRel(root: vault, dir: "", base: "Notes copy", ext: "md")
check("free name when 'Notes copy' is open", firstFree == "Notes copy.md")
write("Notes copy.md")   // now the obvious copy name is taken too
let secondFree = uniqueRel(root: vault, dir: "", base: "Notes copy", ext: "md")
check("collision bumps to a numbered copy", secondFree == "Notes copy 2.md")
check("an existing file is never the chosen target (no clobber)",
      secondFree != "Notes.md" && secondFree != "Notes copy.md")

// 2. Two back-to-back imports of the same source name don't collide: claim the first, then the next is distinct.
let claimA = uniqueRel(root: vault, dir: "", base: "Dropped", ext: "csv")
write(claimA)   // simulate the first import landing on disk
let claimB = uniqueRel(root: vault, dir: "", base: "Dropped", ext: "csv")
check("first of two same-name imports", claimA == "Dropped.csv")
check("second same-name import gets its own path", claimB == "Dropped 2.csv" && claimB != claimA)

// 3. Naming respects the target folder (dropped over a folder).
let inFolder = uniqueRel(root: vault, dir: "Inbox", base: "Memo", ext: "md")
check("name is filed under the drop folder", inFolder == "Inbox/Memo.md")

// 4. Boxable-type filter: the types that get a box are accepted; others are skipped; folders always accepted.
check("md accepted",      accepts(ext: "md",  isDirectory: false))
check("csv accepted",     accepts(ext: "csv", isDirectory: false))
check("MD case-insensitive", accepts(ext: "MD", isDirectory: false))
check("code (swift) accepted", accepts(ext: "swift", isDirectory: false))
check("png skipped",      !accepts(ext: "png", isDirectory: false))
check("pdf skipped",      !accepts(ext: "pdf", isDirectory: false))
check("extension-less file skipped", !accepts(ext: "", isDirectory: false))
check("folder always accepted (even with odd name)", accepts(ext: "weird", isDirectory: true))

print(fails == 0 ? "\nALL PASS" : "\n\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
