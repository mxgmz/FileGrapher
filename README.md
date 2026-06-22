# FileGrapher

A native **macOS SwiftUI** app: a stripped-down, Miro-style infinite canvas whose real job is
**organizing folders and creating Obsidian `.md` notes**. A box *is* a real file; a folder box
*is* a real directory.

> Status: working MVP, actively iterating.

## Highlights
- Infinite, pan/zoom canvas with a dot grid, curved edges, and spawn/resize handles.
- Boxes map 1:1 to files on disk — the **disk is the source of truth**. `board.json` stores only
  layout (positions, sizes, edges) and is reconciled with the real filesystem on launch.
- Folder boxes auto-grow to contain their children; dropping a box into a folder re-files it on disk.
- Title-only boxes by default; reveal content via **Quick Look** (a transient peek popover) or an
  **Expand card** (a persistent in-place card). Markdown renders *and* edits (saved to disk,
  undoable); CSV shows as a read-only table.
- Full **undo/redo** that reverses both board state and disk operations.
- Zero third-party dependencies.

## Requirements
- macOS with the Swift toolchain (Command Line Tools is enough — no full Xcode required).

## Build & run
```sh
# Dev build
swift build

# Build + launch the native app
./build-app.sh && open dist/GraphingApp.app

# Faster, unoptimized build during iteration
./build-app.sh debug
```

## Project layout
| Path | Responsibility |
|---|---|
| `Sources/GraphingApp/App.swift` | `@main`, app/window lifecycle, root view, top bar, menu commands. |
| `Sources/GraphingApp/Model.swift` | Data model, vault/disk sync, all app state, undo/redo engine, folder auto-grow geometry. |
| `Sources/GraphingApp/Canvas.swift` | Infinite canvas, input handling, node/handle/resize views, inline rename. |
| `Sources/GraphingApp/Sidebar.swift` | File/folder tree built from the same nodes as the canvas. |
| `Sources/GraphingApp/FileContent.swift` | Content peek popover, zero-dep Markdown renderer, read-only CSV table. |
| `build-app.sh` | Assembles and ad-hoc-signs `dist/GraphingApp.app`. |

See `CLAUDE.md` for the full architecture notes and `docs/` for the backlog and session handoff log.
