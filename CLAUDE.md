# Graphing App — Project Guide (CLAUDE.md)

> Native **macOS SwiftUI** app: a stripped-down, Miro-style infinite canvas whose real job is
> **organizing folders and creating Obsidian `.md` notes**. A box *is* a real file; a folder box
> *is* a real directory. **Status: working MVP, actively iterating.**

## Quick start
Run from the project root (it's the working directory).
- Dev build: `swift build`
- Build + launch the native app: `./build-app.sh && open dist/GraphingApp.app`
  - Use `./build-app.sh debug` for a faster, unoptimized build during iteration.
- Quit a running instance before relaunching: `pkill -x GraphingApp`

## Critical gotchas (read before touching anything)
- ⚠️ **The project folder name ends in a trailing space**: `/Users/maxgomez/Documents/Graphing app `.
  Always quote paths. Do **not** "fix" it by renaming mid-session — it's the working directory.
- ⚠️ **No full Xcode**, only Command Line Tools. Build with **SwiftPM** (`swift build`), never
  `xcodebuild`. SwiftUI/AppKit come from the macOS SDK, so this works.
- **Swift 5 language mode** (`swiftLanguageModes: [.v5]` in `Package.swift`) — avoids Swift 6
  strict-concurrency churn. Keep it unless you intend to migrate fully.
- **Zero third-party dependencies** by design. Don't add one without a strong reason.
- Permissions: runs in **bypassPermissions** mode (`.claude/settings.local.json`) at the user's
  request — no tool prompts.

## Architecture
SwiftPM executable, single target `GraphingApp`. Source in `Sources/GraphingApp/`:

| File | Responsibility |
|---|---|
| `App.swift` | `@main`, `AppDelegate` (sets `.regular` activation so the bare bundle shows a window), `RootView` → `WelcomeView` / `MainView`, `TopBar`, menu commands (New, Undo/Redo). |
| `Model.swift` | Data (`BoardNode`, `BoardEdge`, `BoardData`), `Vault` (disk + `board.json`), and `AppModel` (`ObservableObject`) holding **all** state + logic: transforms, vault lifecycle, disk sync, mutations, the **undo/redo transaction engine**, and folder auto-grow geometry. |
| `Canvas.swift` | `CanvasView` (infinite canvas, `NSEvent` input monitor, pan/zoom, dot grid, curved edges, spawn handles, resize handles), `NodeView` (note/folder boxes, drag, group-move, region-aware double-tap), `HandleButton` (the `+`), `ResizeHandle` (folder corners), `InlineTitle` (rename field). |
| `Links.swift` | `ManagedLinks` — pure (Foundation-only) read/write of the app-owned `<!-- canvas-links -->` block in a note. The connector↔`[[wikilink]]` bridge (Living Canvas Phase 1): a drawn edge writes a wikilink here, never touching user prose. Headless-tested. |
| `VaultWatcher.swift` | `VaultWatcher` — zero-dep FSEvents wrapper (CoreServices). Watches the vault tree, debounces, reports changed vault-relative paths. The read side of live updates: drives `AppModel.handleDiskChange` → `diskRevision` (cards re-read) + `syncFromDisk` (structure). ⚠️ Needs `kFSEventStreamCreateFlagUseCFTypes` or the callback crashes. |
| `Sidebar.swift` | File/folder tree (`OutlineGroup`) built from the same nodes as the canvas. |
| `FileContent.swift` | The content **peek** popover (`FilePeekOverlay`/`FilePeekCard`), a zero-dep Markdown block renderer (`MarkdownView`/`MarkdownBlock`), and a read-only CSV table (`CSVTableView`/`CSV`). |
| `GitService.swift` | `GitService` — pure (Foundation-only) zero-dep shell-out to the `git` CLI for the vault. **VIEW-ONLY** by contract (Living Canvas time-travel, Sprint 4): the only writes are `enableVersionHistory` (opt-in `git init` + ignore `.graphingapp/` + baseline commit) and `snapshot`; everything else reads (`commits`/`branches`/`uncommittedChangeCount`/`show`/`diffNameStatus`). Never checks out/restores. Headless-tested. |
| `VersionHistory.swift` | `VersionHistoryView` — the top-bar clock popover: opt-in pane when the vault isn't a repo, else Snapshot + read-only commit list + a **branch picker** (`previewBranch`). Also `CommitScrubber` — the bottom strip: drag the commit track (right = live) to `viewCommit`, or show a **branch-preview banner** with Exit when `previewedBranch != nil`. Render-only `HistoryGhostBox` (deleted-since ghosts) lives in `Canvas.swift`. |

Also: `build-app.sh` (assembles + ad-hoc-signs `dist/GraphingApp.app`), `Package.swift`.

## Key concepts
- **Source of truth = disk.** `board.json` (at `<vault>/.graphingapp/board.json`) stores only
  *layout* — positions, sizes, edges. `AppModel.syncFromDisk()` reconciles the board with the real
  files/folders (adds boxes for things created in Obsidian, drops boxes whose files vanished).
- **Coordinates.** A node's `x,y` is the box **center** in world space. `worldToScreen` /
  `screenToWorld` apply `pan` (CGSize) and `zoom`. The canvas draws in *screen* space: each node is
  `.position(worldToScreen(center))` and `NodeView` renders **every dimension × zoom** (frame, fonts,
  padding, radii, strokes via its `scale` property). ⚠️ **Never use `.scaleEffect(zoom)` on a node** —
  that bitmap-scales the rendered view, so text turns blurry when zoomed/enlarged. Render in screen
  space so glyphs are re-rasterized crisp. Tap coords inside a node are in scaled space → ÷ `scale`.
- **Folder auto-grow.** `AppModel.effectiveFrame(of:)` = a folder's stored frame **unioned** with
  (its children's bounds + padding + header). Used everywhere a folder's box matters (render,
  hit-test, edge anchoring, handles). A folder never shrinks below its contents.
- **Undo/redo.** Every mutation runs inside `transaction { }` (nestable, so a spawn = one step),
  which records an undo step that reverses **both board state and disk**. Disk ops are paired:
  `raw*` (perform) vs `t*` (perform **and** register the inverse). Drags/resizes use
  `beginInteraction()` + `endInteraction()` / `endDrag()` to record exactly one step. See
  `// MARK: Undo / redo` in `Model.swift`.
- **Input.** One `NSEvent` local monitor in `CanvasView` handles two-finger scroll→pan,
  pinch & ⌘-scroll→cursor-anchored zoom, and Delete/Backspace→trash. It's gated to the canvas
  region via `model.canvasFrameGlobal` so the sidebar still scrolls normally.
- **Version history / time-travel (`GitService`) is VIEW-ONLY.** ⚠️ Opt-in `git init` + manual
  `snapshot` are the **only** disk writes; **never** `git checkout`/`reset`/`restore` the user's
  files. Scrubbing a past commit only re-routes card/peek *content* (`fileText` → `git show` cache when
  `viewedCommit != nil`); **box positions never move** and `board.json` is **gitignored** (layout never
  time-travels — the "stable stage"). Editing is disabled while `isTimeTraveling`. Structure diff (P2):
  boxes for files added *after* the viewed commit dim + dash (`isAbsentInHistory`); files deleted *since*
  it appear as render-only `HistoryGhost` placeholders (best-effort position). Edge/link diff is deferred.
  Branch-as-layer (P3): `previewBranch(name)` views another branch's tip via the *same* machinery (a branch
  ref is a revision) — `setViewedRevision` unifies scrubber + branch preview; `previewedBranch` is the label.
  Edge/link diff is deferred (needs the read-side `[[link]]`→edge auto-draw).

## Interaction model (locked product decisions)
- **Folder = frame (locked 2026-06-23 · Sprint 5 · see `docs/DESIGN-interaction-polish.md`).** A folder
  is a *container*, not a card: its **header bar + border ring** are the live hit regions; the **interior
  is pass-through** (drag interior → marquee its children; drag header → move the folder). Notes are solid
  cards. **Nothing overlaps** — a drop **pushes** siblings aside; a **pinned** box is immovable and acts
  as an obstacle. Folders are **collapsible** (hide children → header + count) and **expandable** (open a
  folder-note card). *Forward-looking lock — being built in Sprint 5; pre-Sprint-5 behavior still applies
  until each ticket lands.*
- `+` side handle = **same-kind sibling**, connected, placed in that direction (note→note, folder→folder).
- Create a note **inside** a folder: double-click its interior, or the header `+`.
- Dragging a folder moves its contents; dropping a box inside a folder **re-files it on disk**.
- Boxes are **title-only by default**; file content is revealed two ways. **Quick Look** (Space /
  context menu) = a transient floating peek popover. **Expand card** (hover ⤢ / context menu) =
  a persistent in-place card (`node.expanded`, saved in board.json) — header is the drag handle,
  body scrolls/edits; several can be open at once. Markdown renders **and edits** (saves to disk,
  undoable); CSV is a read-only table. Card content renders in screen space (× zoom) so it stays crisp.
  `.md` and `.csv` files both get boxes (`AppModel.boxableExts`); new in-app files are still `.md`.
  Bodies can still be edited in Obsidian too.

## Code style — minimal *and* legible
The `ponytail` plugin (installed) governs **how much code exists**; this governs **what it's named and
how it reads**. Same goal — least cognitive load for the next engineer — different axes, so they
complement. **Target: the shortest code that still reads like a description of the system's behavior.**

When the two pull against each other, resolve in this order:
- **Cut quantity, never clarity.** "One line over fifty" holds only while the line stays legible.
  Don't golf, and never trade an intent-revealing name for fewer characters.
- **A clear name is a legitimate reason to extract a function** — naming, not speculative abstraction
  (which ponytail still forbids). Prefer the fewest *well-named* units, not the fewest units.
- **Terse locals are where they already agree:** `dx`, `dy`, `index`, `i` in a small math/iteration
  scope are correct — don't inflate them to `horizontalTranslationDistance`.

Naming:
- Names state **intent**, not implementation. Functions = actions (`createCustomerInvoice()`), types =
  entities (`BoardNode`), variables = the meaning of the data. Matches the existing code (`effectiveFrame`,
  `syncFromDisk`, `worldToScreen`) — keep that bar.
- No abbreviations unless universal in the domain; no single letters outside small math/loop scopes.
- **Banned generic names:** `data`, `value`, `item`, `thing`, `temp`, `obj`, `helper`, `manager`,
  `util`, `process`, `handle`.
- If a name needs a comment to say what it means, the name is wrong — lengthen the name, drop the comment.
- Comments explain **why** (business rule, constraint, tradeoff, edge case, the non-obvious decision),
  never restate the code.

## Working agreement (how we run this long-term)
Tracked scrum-style. **Every session:**
1. **Start** — read `docs/HANDOFF.md` (where we left off) and `docs/BACKLOG.md` (current sprint + priorities).
2. **During** — keep changes small and buildable; verify with `./build-app.sh debug`.
3. **End** — update `docs/HANDOFF.md` (what changed, current state, next up) and tick items in `docs/BACKLOG.md`.

**Definition of Done:** builds clean, app launches, the change is manually verified, and
`HANDOFF.md` + `BACKLOG.md` are updated.

## Docs
- `docs/BACKLOG.md` — product backlog & current sprint (the board).
- `docs/HANDOFF.md` — session log / pick-up-here notes.
