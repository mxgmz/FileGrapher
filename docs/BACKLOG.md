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
- ⬜ **Marquee multi-select** — rubber-band on empty canvas; then multi-move and multi-delete.
- ⬜ **Live file-watching** — detect notes/folders created or deleted in Obsidian/Finder and
  reconcile without the manual ↻ (DispatchSource/FSEvents on the vault root).
- ⬜ **Fix:** ⌘Z while editing a box title should undo the *text*, not the board.

---

## 🧭 Humanwise functionality audit (2026-06-21)
Stories framed as: *"I've used Miro / FigJam / Obsidian Canvas / Whimsical / Excalidraw —
what do my hands reach for, and what feels broken when it's missing?"* Grouped by expectation
strength. User explicitly requested: **editable connectors**, **editable text size**,
**folder color switching** (all marked ⭐ below).

### Tier 1 — "feels broken without it" (muscle memory)
- 🔄 **Right-click context menu** — ✅ box (rename, add-note-inside, color, text size, reveal, open,
  trash) and ✅ connector (color, style, arrowhead, delete) menus shipped (S2); ⬜ empty-canvas menu
  (paste / select-all / new note) still todo.
- ✅ **Click empty canvas to deselect** — clears box + connector selection. *(S2)*
- ⬜ **Shift-click to add/remove from selection** — hand-pick boxes without a marquee.
- ⬜ **Select all (⌘A)** — select every box.
- ⬜ **Duplicate (⌘D / ⌥-drag)** — copy a box in place or by option-drag. *(Open Q: duplicating a
  note should create a real second `.md` with a "copy" suffix?)*
- ✅ **Copy / cut / paste boxes (⌘C/⌘X/⌘V)** — disk-aware: copy duplicates files ("… copy"),
  cut moves them; paste files into the folder under the cursor; undoable. *(S5)*
- ✅ **Select & delete a connector** — click a line to select (highlight), Delete removes just it. *(S2)*
- ✅ **Resize notes** — note boxes get corner resize handles too (min 110×52). *(S3)*
- ⬜ **Zoom to fit / frame all** — one action to fit everything on screen.
- ⬜ **Keyboard zoom (⌘+ / ⌘- / ⌘0)** — zoom in/out and reset to 100%.

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
- ⬜ **Double-click empty canvas → new note** — mirrors the "double-click inside a folder" gesture.
- ⬜ **Drag a file in from Finder** — drop a `.md` / folder onto the canvas to add it as a box.
- ⬜ **Alignment guides & snapping** — snap to edges/centers with guide lines while dragging.
- ⬜ **Arrow-key nudge** — arrows move selection a few px (Shift = larger step).
- ⬜ **Collapse / expand a folder** — hide a folder's children on the canvas.
- ⬜ **Open in Obsidian** — one-click `obsidian://` deep link from a note. *(also under Obsidian epic)*
- ⬜ **Zoom % indicator** — show current zoom; click to reset.

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
- ⬜ Zoom-to-fit / "frame all" action. *(see audit Tier 1)*
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
- ⌘Z while editing a box title runs board undo instead of text-field undo.
- Auto-grow folder stretches to reach a child flung far away (by design; can surprise).
- Scroll-pan direction & input-monitor gating only verified on the dev machine.
