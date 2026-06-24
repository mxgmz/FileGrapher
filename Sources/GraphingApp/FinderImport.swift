import Foundation

// Drag-in from Finder (Sprint 30): dropping .md/.csv files or a folder onto the canvas copies them into
// the vault and gives each a box at the drop point. Kept in an `extension AppModel` here (rather than in
// Model.swift) to isolate the feature; it reuses Model's undo engine (`transaction`) and the undoable
// external-source copy (`tImport`) so a single ⌘Z removes both the box(es) AND the copied file(s).

extension AppModel {
    /// Import files/folders dragged from Finder. Copies each accepted item into the target folder (or the
    /// vault root) under a collision-safe name and boxes it at `atWorld`. `parent` is the folder the drop
    /// landed over (nil == root). Boxable files (`.md`/`.csv`/code) and folders are accepted; other file
    /// types are skipped silently. The whole import is ONE undo step.
    func importFiles(_ urls: [URL], atWorld: CGPoint, into parent: UUID?) {
        guard let vault else { return }
        let parentFolder = parent.flatMap { node($0) }
        let dir = (parentFolder?.kind == .folder ? parentFolder?.relPath : nil) ?? ""
        // Where each new box's center is stored (relative to the target folder, or world at the root).
        let center = relativeCenter(atWorld, inDir: dir)

        // Accept folders always; accept files only if their type gets a box (boxableExts). A dead/unreadable
        // URL or any other type is dropped here at the trust boundary, never reaching disk.
        let accepted = urls.filter { url in
            guard let isDir = isExistingDirectory(url) else { return false }   // missing/unreadable → skip
            return isDir || AppModel.boxableExts.contains(url.pathExtension.lowercased())
        }
        guard !accepted.isEmpty else { return }

        transaction {
            // Tile multiple drops so they don't stack exactly on one another.
            for (offset, url) in accepted.enumerated() {
                let isDir = (isExistingDirectory(url) == true)
                let base = url.deletingPathExtension().lastPathComponent
                let ext = isDir ? "" : url.pathExtension
                let rel = vault.uniqueRel(dir: dir, base: base, ext: ext)
                tImport(from: url, to: rel)   // copies the file (or whole folder subtree) + registers the undo

                let tiled = CGPoint(x: center.x + CGFloat(offset) * 24, y: center.y + CGFloat(offset) * 24)
                if isDir {
                    // Box the folder at the drop point, then let syncFromDisk box its descendants (it skips
                    // this folder — already known — and adds boxes for everything copied inside it).
                    board.nodes.append(BoardNode(kind: .folder, relPath: rel, x: tiled.x, y: tiled.y,
                                                 width: AppModel.folderSize.width, height: AppModel.folderSize.height))
                    syncFromDisk()
                } else {
                    let newNote = BoardNode(kind: .note, relPath: rel, x: tiled.x, y: tiled.y,
                                            width: AppModel.noteSize.width, height: AppModel.noteSize.height)
                    board.nodes.append(newNote)
                    selection = [newNote.id]
                }
            }
            selectedEdge = nil
            editingId = nil
        }
    }

    /// True/false for an existing file/dir at `url`, or nil when nothing readable lives there — the guard
    /// that keeps a stale or unreadable Finder drag from ever touching the vault.
    private func isExistingDirectory(_ url: URL) -> Bool? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        return isDir.boolValue
    }
}
