# Backlog — Graphing App

Scrum-style board. **Status legend:** ✅ done · 🔄 in progress · ⬜ todo · 🧊 icebox.

## Definition of Done
- Builds clean (`./build-app.sh debug`) and the app launches.
- Behavior manually verified.
- `HANDOFF.md` and this file updated.

---

## 🎯 Current sprint — "Sprint 2" (started 2026-06-21)
**Goal:** make multi-item editing and external-edit awareness feel native.

Committed:
- ✅ **Stability: coordinate-meltdown guard (S10)** — node coords/sizes & `pan` are now clamped
  (`AppModel.worldBound`/`panBound`/`sizeBound`); a corrupt `board.json` self-heals on load
  (`sanitizeBoardGeometry`). Fixes the 99.9%-CPU / WindowServer hang from runaway x-coords (~1e13).
  ⬜ *Follow-up:* trace & plug the source that first seeds a large coordinate (suspect `pan` drift →
  `screenToWorld` on double-click-add / drop-refile).
- ✅ **Marquee multi-select** — rubber-band on empty canvas; then multi-move and multi-delete.
  *(found already fully implemented S10: `marqueeGesture`/`applyMarqueeSelection`/`marqueeOverlay` in
  Canvas.swift, + Shift-drag-adds, + multi-move via `dragGroup`, + multi-delete. Reviewed correct
  end-to-end; **pending Max's visual verify** before closing.)*
- ✅ **Live file-watching (S12)** — `VaultWatcher` (FSEvents, debounced) reconciles notes/folders
  created/deleted/moved in Obsidian/Finder without the manual ↻, and bumps `diskRevision` so open
  cards/peeks re-read live. **Self-write suppression** (`markSelfWrite` + `isRecentSelfWrite`) and a
  mid-interaction guard keep the app's own writes from looping or yanking a drag. *(Found+fixed an
  FSEvents `UseCFTypes` crash. The link auto-draw on external `[[..]]` still needs the read side below.)*
- ✅ **Fix (S20, PR #1):** ⌘Z while editing a box title undoes the *text field*, not the board —
  first-responder-aware Undo/Redo (`FieldEditor` in App.swift) routes to the focused field editor's own
  undo while editing, board undo otherwise.

---

## 🌅 Next sprint — "Sprint 3 · Living Canvas Phase 1" (the spine)
**Goal:** make a connector a *real link* in the file, and make the canvas reflect the vault **live**.
**Spec:** see [`VISION-living-canvas.md`](VISION-living-canvas.md) (full brainstorm 2026-06-21) — the
*what & why*; the table below is the *what-to-build*. Design law for all of it: **"alive but sober."**

Committed (Phase 1 — notes linking + live read, **no git required**):
- ✅ **Connector → real `[[wikilink]]` (bidirectional, S12 write + S19 read)** — ✅ **write side (S12):**
  drawing an edge between two `.md` notes (manual connect, `+`-handle spawn) writes `[[Target]]` into the
  source note's managed `<!-- canvas-links -->` block; deleting removes it; **undo reverses canvas + disk
  together**. ✅ **read side (S19):** see below — the block now auto-draws/drops edges live.
- ✅ **Managed-links block round-trip (S12)** — `ManagedLinks` (`Links.swift`) owns *only* the text
  between the markers; user prose is never touched. Headless-tested (12 cases: seams, dedup,
  alias/heading strip, removal, round-trip). *(Optional YAML-frontmatter mirror still parked.)*
- ✅ **Read side: `[[links]]` → auto-drawn edges (S19)** — `AppModel.reconcileLinkEdges()` in `syncFromDisk`
  makes each note's managed block the source of truth: a `[[Target]]` (app/agent/other-machine) auto-draws an
  edge live (via `VaultWatcher`); a removed link drops its edge. New `BoardEdge.linkBacked` separates real
  link edges from hand-drawn ones — **legacy edges are never auto-dropped**. **Ambiguity-safe** for the live
  vault's many `Untitled` (no guessed auto-draw; an existing edge is kept while its name persists in the
  block). Resolves `[[Name]]` by basename, `[[folder/Name]]` by path. Headless 9/9 + live integration
  verified. *(Reading prose wikilinks outside the managed block is deferred — the block round-trips cleanly
  with edge-delete; prose links can't be removed by deleting an edge.)*
- ✅ **Live file-watching (S12)** — `VaultWatcher` (FSEvents, debounced): **content** (open cards/peeks
  re-read via `diskRevision`, edit-guarded) and **structure** (create/delete/move boxes via
  `syncFromDisk`) update live, with **self-write suppression** so the app's own writes don't loop. *Links*
  don't auto-draw on external `[[..]]` yet — that's gated on the read side above.
- ✅ **Folder geometry hardening (S14)** — three fixes after live-watch exposed latent fragility:
  **(1) move-aware `syncFromDisk`** (inode `BoardNode.fileId` → an external rename follows the box, keeping
  position+UUID, instead of collapsing the subtree to a corner); **(2) heal stranded children**
  (`reinInStrandedChildren` at load → no folder auto-grows to an unclickable size; fixed Max's
  114148×98109 Folder 6); **(3) spawn new boxes near their parent**, not a fixed corner. Heal + mirror
  verified on the real board; **Fix 1 still needs an isolated end-to-end verify** (live-vault test tangled
  with concurrent in-app dragging — don't stress-test the live vault).
- ✅ **Conflict default = non-destructive reload banner (S20, PR #2)** — an external change to a file
  whose card/peek is mid-edit raises a per-file conflict (`diskConflicts`, reusing self-write suppression;
  suppressed while time-traveling) and shows a sober "Updated on disk" banner: **Reload** re-reads disk,
  dismiss keeps editing. Headless 8/8. (The ghost overlay / safe live-overwrite is still the parallel track 3a.)

Later phases (tracked in the spec, not this sprint): **P2** typed/labeled links · **P3** code references
(derived + comment-annotation) · **P4** folder-notes · **3a** ghost overlay + live block-flow + soft-lock
+ presence · **3b** git time-travel (loupe review, commit scrubber, branch-as-layer).

---

## 🔮 Sprint 4 (planned, design locked 2026-06-22) — Living Canvas 3b · Git time-travel (prototype)
**Goal:** scrub the canvas through the **vault's** git history — **VIEW-ONLY** (render past state via
`git show`; never `git checkout` or touch the user's files; disk always stays at working state).
Max chose to go straight at 3b (accepting it builds some of 3a's ghost grammar along the way).

**Decisions locked:**
- **Enablement = opt-in `git init`** — an explicit **"Enable Version History"** button (vault isn't a repo
  yet): `git init` + `.gitignore` the `.graphingapp/` sidecar + an initial commit. Non-destructive to files.
- **History = manual Snapshot** — a "Snapshot" button commits current state on demand; the user's own git
  commits also appear. (No auto-commit-on-change — too noisy for the prototype.)
- **board.json gitignored** — layout/positions never time-travel (the "stable stage", spec §5.3).
- **Zero-dep** — shell out to the `git` CLI; graceful "git not found / not a repo" fallback.
- **Build & test on a throwaway repo-vault, NOT the live `Graph test`** (S14 lesson: don't touch the live vault).

**Stages:**
- ✅ **P0 — Plumbing + opt-in (S15).** `GitService.swift` (pure Foundation, zero-dep git shell-out,
  VIEW-ONLY): repo detection (`isRepo`), `enableVersionHistory` (init + gitignore `.graphingapp/` + baseline
  commit), `snapshot`, and read-only `commits`/`branches`/`currentBranch`/`uncommittedChangeCount`/`show`/
  `diffNameStatus`. Wired into `AppModel` (off-main, `versionHistoryEnabled`/`commits`/`uncommittedCount`/
  `gitBusy`); top-bar **clock popover** (`VersionHistory.swift`) = opt-in pane → Snapshot + read-only commit
  list. **Headless-tested 22/22 on a throwaway repo**; build clean; app alive; live vault untouched.
  ✅ *UI/disk-verified S19* — opt-in pane → Enable → `.git`+`.gitignore(.graphingapp/)`+baseline commit
  (author GraphingApp, sidecar ignored); external edit → "1 uncommitted change" → Snapshot → new commit.
- ✅ **P1 — Scrubber + content time-travel (S16).** `CommitScrubber` bottom strip (right = live, drag left
  through HEAD→older) drives `AppModel.viewCommit`; expanded cards **and** peeks render `git show
  <commit>:<path>` (via a `historicalContent` cache + commit-aware `fileText`); **box positions stay fixed**,
  disk untouched, editing disabled while traveling, absent files show "Not in this version". **Headless 7/7**
  on a throwaway repo (incl. the added-later→absent path); build clean; app alive; live vault unaffected.
  ✅ *UI-verified S19* — scrub to Baseline reverts card text + shows orange read-only clock + "Not in this
  version"; Back to Live restores; boxes never moved; nothing written on disk.
- 🔄 **P2 — Structure + link diff (S17, box half done).** ✅ **Boxes fade in/out**: files added *after* the
  viewed commit dim + dash (`isAbsentInHistory`); files deleted *since* show as render-only `HistoryGhost`
  placeholders (`GitService.filesAtCommit` + `deletedSinceGhosts`, best-effort position below the surviving
  parent folder). Headless-verified; build clean; live vault unaffected. ✅ *Edge/link diff built (S19)* —
  `historyEdgeDiff()` parses each note's `[[links]]` from the loaded `historicalContent` (no extra git):
  current link edges absent at the commit **dim+dash** (`isEdgeAbsentInHistory`/`historyAddedEdges`); links
  present then but undrawn now render as faded **`GhostEdgeLine`** ghosts (`historyGhostEdges`). Shared
  `linkTargetResolver` with the read side. Headless **6/6**; build clean. ✅ *UI-verified S19* — at v1,
  Apex→Beta solid, Apex→Delta dim+dashed (added-later), faded Apex→Gamma ghost (existed then); Back to Live
  restored both + cleared the ghost. ✅ *Ghost (box) placement UI-verified S19*. **P2 feature-complete.**
- ✅ **P3 — Branch-as-layer (S18).** `AppModel.previewBranch(name)` views another branch's tip via the same
  `setViewedRevision` machinery as the commit scrubber (a branch ref is a revision): the branch's content
  shows in cards, files only on the branch appear as deleted-since ghosts, files not on it dim. Branch picker
  in the panel (`branches.count > 1`); purple preview banner + Exit in the scrubber. **Headless 6/6** on a
  throwaway repo (edit/add/delete across branches); build clean; live vault unaffected. ✅ *UI-verified S19*
  — Preview branch → experiment: Spec→v2, Ideas dims, Experiment ghosts in, purple banner + Exit → live.
  VIEW-ONLY proven: fixture stayed on `main`, clean, no session checkouts in reflog.
- Later refinement: **the loupe** — render the diff only under a draggable lens (focus + perf).

---

## 🧭 Humanwise functionality audit (2026-06-21)
Stories framed as: *"I've used Miro / FigJam / Obsidian Canvas / Whimsical / Excalidraw —
what do my hands reach for, and what feels broken when it's missing?"* Grouped by expectation
strength. User explicitly requested: **editable connectors**, **editable text size**,
**folder color switching** (all marked ⭐ below).

### Tier 1 — "feels broken without it" (muscle memory)
- ✅ **Right-click context menu** — ✅ box (rename, add-note-inside, color, text size, reveal, open,
  trash) and ✅ connector (color, style, arrowhead, delete) menus (S2); ✅ empty-canvas menu
  (New Note at cursor / Paste / Select All) *(S20, PR #4)*.
- ✅ **Click empty canvas to deselect** — clears box + connector selection. *(S2)*
- ✅ **Shift-click to add/remove from selection** — hand-pick boxes. *(found implemented S10, `select()` in Canvas.swift; needs Max visual verify)*
- ✅ **Select all (⌘A)** — select every box. *(found implemented S10, `handleKey` case "a"; needs Max visual verify)*
- ✅ **Duplicate (⌘D / ⌥-drag) (S20, PR #4)** — ⌘D nudges a copy off the original; ⌥-drag duplicates
  then drags the copies. Reuses the disk-aware copy path → a real second `.md` with a "copy" suffix
  *(Open Q answered: yes)*. ⌥-drag = two undo steps (move + create).
- ✅ **Copy / cut / paste boxes (⌘C/⌘X/⌘V)** — disk-aware: copy duplicates files ("… copy"),
  cut moves them; paste files into the folder under the cursor; undoable. *(S5)*
- ✅ **Select & delete a connector** — click a line to select (highlight), Delete removes just it. *(S2)*
- ✅ **Resize notes** — note boxes get corner resize handles too (min 110×52). *(S3)*
- ✅ **Zoom to fit / frame all (S20, PR #3)** — Zoom to Fit (⌘9 + TopBar button) frames all boxes with
  padding; empty board falls back to reset. Headless 16/16.
- ✅ **Keyboard zoom (⌘+ / ⌘− / ⌘0) (S20, PR #3)** — viewport-center-anchored in/out (×1.2) + reset to 100%.

### Tier 2 — "I'll reach for this within a day"
- 🔄 ⭐ **Editable connectors (Miro-style)** — ✅ drag from a box `+` handle onto an existing box to
  connect manually (S2); ⬜ drag an endpoint onto a different box to re-route; ⬜ reshape the line.
- 🔄 **Connector style controls** — ✅ curved / straight + color + arrowhead on/off (S2);
  ⬜ elbow, thickness, both-ended arrows. (Supersedes the old "arrowhead toggle" open question.)
- ⬜ **Connector labels** — type a label on a connector ("depends on", "leads to").
- ✅ ⭐ **Folder color switching** — per-box accent (9-color palette + Default); colors icon, border,
  folder header & bg. *(S2)*
- ✅ ⭐ **Editable text size** — Small / Medium / Large / Extra Large title sizes per box. *(S2; board
  default still todo)*
- ✅ **Box color / accent (notes too)** — same Color control on note boxes, not only folders. *(S2)*
- ✅ **Double-click empty canvas → new note** — mirrors the "double-click inside a folder" gesture.
  *(found already implemented; confirmed S20, PR #4)*
- ⬜ **Drag a file in from Finder** — drop a `.md` / folder onto the canvas to add it as a box.
- ⬜ **Alignment guides & snapping** — snap to edges/centers with guide lines while dragging.
- ⬜ **Arrow-key nudge** — arrows move selection a few px (Shift = larger step).
- ⬜ **Collapse / expand a folder** — hide a folder's children on the canvas.
- ⬜ **Open in Obsidian** — one-click `obsidian://` deep link from a note. *(also under Obsidian epic)*
- ✅ **Zoom % indicator (S20, PR #3)** — TopBar shows the live zoom %; clicking it resets to 100%.

### Tier 3 — power & polish
- ⬜ **Align & distribute selected** — align left/center, distribute evenly.
- ⬜ **Group boxes (non-folder)** — visual group that moves together without being a real directory.
- ⬜ **Z-order** — bring-to-front / send-to-back for overlapping boxes.
- ⬜ **Lock a box** — prevent accidental dragging of an anchor.
- ⬜ **Box icon / emoji** — small glyph for fast visual scanning.
- ⬜ **Note body preview** — peek a note's first lines (hover / expand) without leaving the canvas.
- ⬜ **Remember viewport per vault** — reopen the board at the last pan + zoom.

---

## 📋 Backlog (prioritized)

### Epic: Canvas & navigation
- ✅ Zoom-to-fit / "frame all" action + keyboard zoom (⌘+/−/0/9) + click-to-reset zoom %. *(S20, PR #3)*
- ⬜ Minimap / overview.
- ⬜ Keyboard navigation: arrows nudge selection, Tab cycles boxes. *(nudge in audit Tier 2)*

### Epic: Connections
- ✅ Manually connect two existing boxes (drag from a handle onto a target box). *(S2)*
- ✅ Select and delete a connection. *(S2)*
- 🔄 Connector-style toggle — ✅ curved / straight + color + arrowhead on/off (S2); ⬜ elbow.
- ⬜ ⭐ Editable connector endpoints / re-route + labels. *(audit Tier 2)*

### Epic: Boxes & content
- ⬜ Inline note-body editing (markdown) — deferred from MVP (title-only by decision).
- ✅ Box color / accent (notes + folders). *(S2)*
- 🔄 ⭐ Editable title text size — ✅ per-box, incl. "Huge" 2× tier (S2–S3); ⬜ board default. *(audit Tier 2)*
- ✅ Resize notes (corner handles, min 110×52). *(S3)*
- ✅ Title text scales with box size (notes; multiplies with Text Size menu). *(S7)*

### Epic: Inline file content (viewer/editor) — ⭐ Phase 1 shipped (S6)
*"An open Notion that lives on my computer."* Decision: **peek popover**, **editable from the start**.
- ✅ **Peek affordance** — Space on the selected box, hover **⤢** chevron, or "Show Content" (canvas +
  sidebar menus). Floating card beside the box; Esc / tap-outside / ✕ closes. *(S6)*
- ✅ **Markdown rendering** — zero-dep block renderer (headings/lists/quote/fenced-code/hr + inline
  styling), themed for light & dark. *(S6)*
- ✅ **Markdown editing** — raw-text editor toggle, saves to the `.md` on disk, undoable. *(S6)*
- ✅ **CSV rendering** — quote-aware parse → read-only table (header, zebra, monospaced, 1000-row cap).
  `.csv` files now get boxes. *(S6)*
- ✅ **Perf/UX** — content built lazily only for the open box; fixed readable card size. *(S6)*
- ⬜ **Phase 2** — CSV cell editing; dedicated code view + auto-box code files (.swift/.json/…);
  syntax highlighting for code blocks; live-styled markdown editor (NSTextView).
- ✅ **Phase 3** — persistent **in-place cards**: notes expand into editable content cards (header =
  drag handle, body scrolls/edits), several open at once, saved in board.json, crisp under zoom. *(S8)*
- ⬜ **Phase 3 polish** — inline CSV/text editing; remember a card's custom size across collapse;
  double-click header to rename; per-card collapse animation tuning.
- Open Qs: board-default to show content for some boxes? external-edit refresh while a card is open?

### Epic: Obsidian integration
- ⬜ "Open in Obsidian" via `obsidian://` deep link.
- ⬜ Respect Obsidian config (ignore `.obsidian/`, honor excluded files).

### Epic: Productivity
- ⬜ Search / quick-open (jump to a note by name).
- ⬜ Recent vaults list.

### Epic: Appearance
- ✅ Light/dark theme toggle (S3).
- ⬜ "Follow system" as a third theme option (S3 shipped a 2-way toggle by request).
- ⬜ Board-default text size (so new boxes can start bigger). *(also under Boxes epic)*

### Epic: Quality & infra
- ⬜ Unit tests for `AppModel` logic (`uniqueRel`, `effectiveFrame`, undo round-trips) where headless-testable.
- ⬜ App icon + window-chrome polish.
- ⬜ Verify scroll-pan direction & monitor coordinate gating on other setups/displays.

---

## 🧊 Icebox
- Multi-window / tabs.
- iCloud / sync across machines.
- iPadOS / mobile.
- Plugin or theming system.

---

## ✅ Done (archive)

### Session 8 — in-place content cards, file-viewer Phase 3 (2026-06-21)
- ✅ Notes expand into persistent, editable in-place cards (`node.expanded`); header drags, body
  scrolls/edits; markdown editable inline; renderers made zoom-aware (crisp); scroll no longer hijacked
  over cards/peek. *(interactive bits need manual eyeball.)*

### Session 7 — title text scales with box (2026-06-21)
- ✅ Note title font couples to box size (`BoardNode.sizeScale`), multiplies with the Text Size menu.

### Session 6 — inline file content peek, Phase 1 (2026-06-21)
- ✅ Peek popover (Space / ⤢ / Show Content) rendering markdown (zero-dep block renderer, themed) and
  CSV (read-only table); markdown editable → saves to disk, undoable. `.csv` files now appear as boxes;
  type-aware icons. *(rendered visuals need manual eyeball — couldn't screenshot in-env.)*

### Session 5 — copy/cut/paste boxes (2026-06-21)
- ✅ ⌘C/⌘X/⌘V for boxes: disk-aware (copy duplicates as "… copy", cut moves), files into the folder
  under the cursor, preserves group layout, undoable. Cut sources render dimmed. *(needs manual keypress
  verify — couldn't automate in-env.)*

### Session 4 — fix blurry text on zoom/enlarge (2026-06-21)
- ✅ Removed per-node `.scaleEffect(zoom)`; `NodeView` renders in screen space (every dim × zoom) so
  text stays crisp at any zoom level and font size. CLAUDE.md Coordinates note updated with a ⚠️.

### Session 3 — resizable notes · theme toggle · Huge text (2026-06-21)
- ✅ Note boxes get corner resize handles (per-kind min size; folders unchanged).
- ✅ Light/dark theme toggle in the top bar — persisted, seeded from system appearance on first run.
- ✅ "Huge" (2×) tier added to the Text Size menu.

### Session 2 — box color/size · selectable & editable connectors (2026-06-21)
- ✅ Per-box accent color (9-color palette + Default) on notes & folders; right-click + sidebar menus.
- ✅ Per-box title text size (Small / Medium / Large / Extra Large) with active-size check-mark.
- ✅ Connectors selectable (tap), highlighted, and individually deletable (Delete key / menu).
- ✅ Connector restyle: color, curved/straight, arrowhead on/off (right-click menu).
- ✅ Manual connect: drag from a box `+` handle onto another box (tap still spawns a sibling).
- ✅ Backward-compatible schema (optional fields; old `board.json` round-trips byte-identical, verified).

### Sprint 1 — MVP → smoothness → folders/connectors → undo (2026-06-21)
- ✅ SwiftPM project (no Xcode), `build-app.sh` bundling `dist/GraphingApp.app`, ad-hoc signed.
- ✅ Vault picker, `board.json` persistence, disk ⇄ board sync (`syncFromDisk`).
- ✅ Infinite canvas: drag-pan + two-finger scroll-pan + momentum, cursor-anchored pinch/⌘-scroll
  zoom, dot grid, spring animations, grab cursor.
- ✅ Note boxes ↔ `.md`; folder boxes ↔ directories; sidebar file tree.
- ✅ Miro `+` spawn handles → same-kind connected sibling.
- ✅ Create note inside a folder: double-click interior + header `+`.
- ✅ Inline rename (name pre-selected, Esc cancels); Delete/Backspace → Trash.
- ✅ Folders auto-grow to fit; corner resize (never below contents); group-move; drop-to-refile; nesting.
- ✅ Curved edge-to-edge connectors with direction arrowheads.
- ✅ Full undo/redo (⌘Z / ⇧⌘Z) reversing **both** board state and disk; toolbar buttons.

---

## 🐞 Known issues
- ✅ *(fixed S20, PR #1)* ⌘Z while editing a box title now undoes the text field, not the board.
- Auto-grow folder stretches to reach a child flung far away (by design; can surprise).
- Scroll-pan direction & input-monitor gating only verified on the dev machine.
