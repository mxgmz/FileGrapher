# Session Handoff — Graphing App

Newest first. **At each session's end, add an entry**: what changed, current state, next up,
open questions. At a session's start, read the top entry to pick up where we left off.

---

## 📍 PICK UP HERE — checkpoint (2026-06-21, end of Sessions 1–9)

**State:** Working, fairly polished MVP. `swift build` + `./build-app.sh debug` clean; app launches and
runs against the live vault `/Users/maxgomez/Documents/Graph test/`. Files: `App.swift`, `Model.swift`,
`Canvas.swift`, `Sidebar.swift`, `FileContent.swift`.

**Recently built (S2–S9), newest first:** in-place content **cards** (expand notes → editable markdown /
read-only CSV; header drags, body scrolls/edits) + a canvas-freeze fix; **Quick Look** peek popover;
`.csv` files appear as boxes; **light/dark** toggle; **copy/cut/paste** boxes (⌘C/X/V, disk-aware,
undoable); selectable/restyleable **connectors** + manual connect; per-box **color** & **text size**
(+ size couples to box dims); **resizable notes**; **crisp text** (screen-space rendering, never
`.scaleEffect` a node).

> ⚠️ **VERIFICATION DEBT — the #1 thing to resolve.** This environment can't screenshot or drive the UI
> (screen-recording denied), so everything since S5 was verified only by *build + launch-stays-alive +
> headless logic tests + board.json inspection* — **not by eye.** Max is the visual verifier. Quick
> manual pass to clear the debt:
> 1. **⌘C/⌘X/⌘V** — select box → ⌘C → ⌘V makes a "… copy"; ⌘X → hover folder → ⌘V re-files; ⌘Z reverses.
> 2. **Quick Look** — select a note → **Space** (formatted md; pencil edits & saves; Esc closes).
> 3. **Expand card** — hover note → **⤢** (or right-click → Expand Card); drag by header; scroll body;
>    pencil edits; **Esc** / chevron collapses. Two-finger scroll over empty canvas pans; over a card scrolls.
> 4. **Color / Text Size / resize / text-scales-with-box / theme toggle** look right.
>
> Open question from S9: when "couldn't move other things" happened, was it **pan** (fixed) or also
> **dragging boxes**? If box-drag is still stuck near a card, suspect the expanded-card gesture mask
> (`including: .subviews`).

**Recommended next (pick one):** **Multi-select** (marquee + Shift-click + ⌘A — biggest friction gap,
pairs with the multi-target color/copy/delete already built) · or file-viewer **Phase 2/3 polish**
(inline CSV edit, remember card size across collapse, double-click-header rename) · or **Foundation**
(live file-watching, fix ⌘Z-in-rename).

**Gotchas:** project dir name has a **trailing space** — always quote, never `cd` into it (run from the
existing cwd). **No Xcode** → SwiftPM only. **Can't screenshot** in-env. Demo files `Peek demo.md` +
`sample.csv` were added to the vault for testing — safe to Move-to-Trash in-app.

---

## 2026-06-21 — Session 11 — finding: "Marquee multi-select" is already built
**Context:** picked Sprint 2's next item, Marquee multi-select. On inspection the **entire feature is
already implemented** in `Canvas.swift` and was just never verified/ticked:
- Marquee: `marqueeStart/Current/Base` state + `marqueeGesture` (DragGesture ≥4px on `background`,
  `.local`), `applyMarqueeSelection` (screen→world rect, selects nodes whose `effectiveFrame`
  intersects), `marqueeOverlay` (accent rubber-band). Shift-drag is additive (`marqueeBase`).
- Shift-click toggle: `NodeView.select()`. Select-all: `handleKey` ⌘A. Multi-move: node `dragGesture`
  via `model.dragGroup(for:)` (folders carry descendants, one move per id, no double-move).
  Multi-delete: `delete(model.selection)`. Multi copy/cut: `clipboardEntries(from: selection)`.
- Layering checked: `world` ZStack has no fill/contentShape, so empty-canvas drags fall through to the
  marquee; keyboard handler bails (`return event`) while editing a title / text field is first responder,
  so ⌘A/Delete don't fire mid-type. Reviewed correct end-to-end.

**State:** builds clean, app alive. **Owe Max a 60-sec visual pass** (marquee a few boxes → all
highlight; drag one → group moves; Delete → all gone, ⌘Z restores; Shift-click toggles; ⌘A selects all).
Backlog ticked ✅ *pending that visual verify*. **Next:** if it checks out, take Sprint 2's **live
file-watching** or the **S10 coord-jump root-cause**; if a marquee bug shows up, fix it.

**Bug fix (S11) — "after expanding the code demo it won't let me select anything else":** this was the
lingering half of S9's "seized my view" (S9 fixed pan; selection/clicks were still stuck near a card).
Root cause hypothesis: `CodeView`'s selectable code text (`.textSelection(.enabled)` + `.fixedSize(horizontal:)`
in a 2-axis `ScrollView`) reports a hit region as wide as the longest line — an invisible strip that
escapes the card's visual clip and eats clicks on boxes beside it. **Fix:** bound the expanded card body's
hit-testing to its frame via `.contentShape(Rectangle())` + `.clipped()` on `cardBody` (Canvas.swift ~711).
Low-risk, enforces the correct invariant (a card never captures input outside its own box) for all card
types. **Pending Max's verify**: expand the code card → click other boxes → they should select now. If
still stuck, the cause is instead the expanded-node `including: .subviews` gesture mask — instrument
`select()`/marquee and reproduce.

---

## 2026-06-21 — Session 10 — fix: runaway coordinates pinned the CPU / hung WindowServer ("crashed again")
**Symptom (user):** app "crashed again" — three screenshots showed **GraphingApp at 99.9% CPU**,
WindowServer "experienced a problem", and the Dock crash-looping every ~10s. Not a clean crash: a
**runaway compute/layout spin** that starved WindowServer. No GraphingApp `.ips` (it spun, didn't crash).

**Root cause:** `board.json` held **astronomically large x-coordinates** — `Untitled.md` at x ≈ **-1.5e13**
and the whole `Folder 4` / `Folder 7` cluster at x ≈ **-1.26e12** (y was fine; only x exploded; 3/31
nodes were sane). SwiftUI laying out / `.position()`-ing views at 1e12–1e13 pins the CPU and drags
WindowServer down. The grid-loop and folder-recursion spins were already guarded (S-earlier) — this was
a **new vector: unbounded coordinate values** reaching the renderer. Likely seeded by an absolute
placement (`screenToWorld` on double-click / re-file) while `pan` had drifted large; pan was never clamped.

**Fix (code, `Model.swift`):** made out-of-range geometry impossible to render:
- `AppModel.worldBound = 1_000_000`, `panBound = 5_000_000`, `sizeBound = 8…50_000` + static
  `clampCoord` / `clampPan` / `clampSize` helpers.
- `pan` now clamps in a `didSet` (covers the scroll handler + zoomToward + centering).
- `setPosition` / `setFrame` clamp every written coordinate & size.
- `sanitizeBoardGeometry()` runs in `openVault` after load and **resaves if it changed anything** — a
  corrupt board now self-heals (blunt clamp to ±worldBound) instead of hanging the machine.

**Recovery (live vault `/Users/maxgomez/Documents/Graph test/`):** backed up board.json
(`board.json.bak-20260621-212559`), then **layout-preservingly** repaired the 19 runaway nodes — shifted
the Folder 4/Folder 7 cluster as a rigid body to centroid x≈120k (internal arrangement intact), parked the
lone -1.5e13 note at origin. All 31 nodes now within ±1e6.

**Follow-up — "you made everything huge":** the layout-preserving repair parked the Folder 7 cluster at a
new centroid but left `Folder 7/test` at its old sane spot, and the user had since drag-refiled notes into
Folder 7 — so its children were scattered ~100k apart AND its **stored** frame had been inflated to
101329×102728 (auto-grow never shrinks below the stored frame). Net: a 100k×100k folder box = "huge."
Fix (board.json only, app quit first so writes stick): repacked Folder 7's direct children beneath the
intact Folder 6 subtree (folders moved as rigid bodies) **and reset Folder 7's stored frame to 340×230
centered on its children**. Folder 7 now auto-grows to **2170×1491** (normal); no folder >4000px.

**Verified:** `swift build` + `./build-app.sh debug` clean; relaunched → CPU settles to **~0–7%** at rest
(initial ~60% was first-render of 35 nodes + 3 expanded cards, not a loop); board.json = 0 out-of-bounds,
Folder 7 stored 340×230. Meltdown + giant folder gone. **Backups:** `board.json.bak-*` in `.graphingapp/`.
**Visual pass still owed to Max** (per verification debt): confirm boxes appear where expected and Folder 7
contents look right.

**Next up:** find the exact arithmetic that first seeds a large coordinate (suspect `pan` drift feeding
`screenToWorld` on double-click-add / drop-refile) — the clamps make it non-fatal, but plugging the source
would stop boxes ever jumping. Otherwise resume Sprint 2 (marquee multi-select / live file-watching).

---

## 2026-06-21 — Session 9 — fix: expanded card froze the canvas ("seized my view")
**Symptom (user):** edited a note, filed it into Folder 6, expanded it (worked), then the canvas was
stuck — couldn't pan/move to anything else; the card "seized the view." (Board had **two** expanded
cards in Folder 6: `Untitled 3.md` + `Peek demo.md`.)

**Root cause:** the scroll/pan input monitor gated on a **sticky** `AppModel.contentScrollHover` flag
set by the card body's `.onHover`. SwiftUI `.onHover` routinely drops the exit (`false`) callback when a
view appears under the cursor / is covered / changes — so the flag latched `true` and the monitor then
refused to ever pan or zoom (it believed the cursor was permanently over a card). Trackpad pan/zoom dead.

**Fix:**
- Made it **stateless**: the monitor now checks at scroll time whether the cursor's world point is
  actually inside an expanded card's `effectiveFrame` (or peek is open) before declining to pan. No
  latching flag. Removed `contentScrollHover` + the `.onHover` setter.
- Added an **Esc escape hatch** (handled before the text-focus guard, except during inline rename):
  exits a card's text editor → else closes the peek → else collapses the selected card. So the canvas
  can never trap you with no way out.

**Recovery:** collapsed all expanded cards in the live vault's board.json (reset to default size) so the
user starts unstuck.

**Current state:** `swift build` + `./build-app.sh debug` clean; relaunched, alive & unstuck.
⚠️ Still can't verify interactively in-env — if "can't move other *boxes*" meant drag (not pan) is also
broken, the next suspect is the expanded-card gesture mask (`including: .subviews`); revisit if reported.

**Quick verify:** expand a card, two-finger scroll over empty canvas → should pan; over the card → card
scrolls; Esc collapses.

---

## 2026-06-21 — Session 8 — in-place content cards (Phase 3 of the file viewer)
**Ask:** the "open Notion that lives on my computer" — boxes that expand into editable content cards,
staying open and arrangeable on the canvas (chosen over multi-select / Phase 2 for "what's next").

**What shipped:**
- **`BoardNode.expanded: Bool?`** (persisted, backward-compat) + `isExpanded`. `AppModel.setExpanded`
  / `toggleExpand` (undoable): expanding grows the note to `expandedSize` 360×320 (keeps larger custom
  size), collapsing returns it to the default note size.
- **`NodeView` expanded card:** `content` branches folder → `expandedCard` → `noteBox`. Card = header
  (icon + title + edit toggle + collapse chevron) over the content body (the **same renderers**,
  now zoom-aware: `MarkdownView`/`CSVTableView` take a `scale` = zoom, so card text stays crisp).
  Markdown is **editable inline** (pencil ⇄ preview; saves via `saveFileContent` on toggle/collapse/
  disappear). CSV/text read-only.
- **Drag model:** the box's own drag/tap are masked (`.gesture(_, including: node.isExpanded ?
  .subviews : .all)`) so the **header is the drag handle** and the body scrolls/selects/edits. Resize
  handles still size the card; `sizeScale` (S7) is *not* applied when expanded (header stays normal).
- **Entry points:** hover **⤢** now *expands* (was peek); context menu + sidebar get
  "Expand/Collapse Card" and "Quick Look" (peek). Space still = Quick Look peek.
- **Scroll fix:** input monitor no longer hijacks two-finger scroll when `peekId != nil` or the pointer
  is over a card body (`AppModel.contentScrollHover`) — so cards/peek scroll natively instead of panning.

**Verified:** `swift build` + `./build-app.sh debug` clean; launches & stays alive. Smoke-tested the new
render path by force-setting `expanded:true` on the demo note in board.json → app rendered the card
without crashing. **Left the demo note expanded** so the feature shows on launch. ⚠️ Interactive bits
(expand/collapse animation, header-drag vs body-scroll, inline edit save, crispness) are **unverified by
eye** — no screenshot/automation in-env. Worth a real click-through.

**Known risks / next polish:** header-drag vs body-scroll gesture masking is the riskiest part — if a
card's body drags the box (or the header won't drag), that's where to look. Collapsing loses a custom
expanded size (resets to default note size) — acceptable for v1. CSV/text not yet editable inline.

**Next up:** multi-select (still unbuilt) · Phase 2 (CSV cell edit, code files + highlighting) ·
manual-verify S5–S8.

**Quick verify:** `pkill -x GraphingApp; ./build-app.sh debug && open dist/GraphingApp.app` → hover a
note, click ⤢ (or right-click → Expand Card).

---

## 2026-06-21 — Session 7 — title text scales with box size (notes)
**Ask:** "make it so text size moves with box size also."

**What changed:** added `BoardNode.sizeScale` (notes only) = `min(width/dw, height/dh)` vs the default
note size, clamped 0.5–6. `NodeView.noteBox` multiplies the title font + icon + spacing by it, so
resizing a note grows/shrinks its text live (the font reads the frame, so it tracks the drag with no
extra wiring). 1.0 at the default size → no change for existing boxes; stacks multiplicatively with the
Text Size menu (`fontScale`) and zoom. Folders unaffected (header is fixed height).

**Refactor:** moved the default note size to a module-level `gappDefaultNoteSize` (nonisolated) so the
`BoardNode` value type can reference it without a MainActor-isolation warning; `AppModel.noteSize`
now aliases it.

**Current state:** `swift build` + `./build-app.sh debug` clean (no warnings); launches & stays alive.
⚠️ Visual scaling unverified by eye (no screenshot in-env) — quick check: resize a note via a corner
handle, text should grow with it.

**Quick verify:** `pkill -x GraphingApp; ./build-app.sh debug && open dist/GraphingApp.app`

---

## 2026-06-21 — Session 6 — inline file content peek (markdown render+edit, CSV table) — Phase 1
**Ask:** see file contents on the canvas — "an open Notion that lives on my computer." Render .md
(and code) and .csv readably/with formatting, as an *option* (Space / Shift-click-style pop-up),
**editable**, smooth, not cluttered. Brainstormed first; user chose **peek popover** + **editable
from the start** (md edit + csv read-only). See BACKLOG "Inline file content" epic for the full plan.

**What shipped (Phase 1):**
- **New file `FileContent.swift`:** `FilePeekOverlay` (dim backdrop + card, positioned beside the box,
  clamped on-canvas, tap-outside/Esc/✕ to close), `FilePeekCard` (header: name · edit toggle · open-in-app
  · close; body switches on file type). Zero-dep **Markdown** renderer (`MarkdownBlock.parse` →
  headings/paras/bullets/ordered/quote/fenced-code/hr; inline bold/italic/code/links via
  `AttributedString(markdown:)`), themed for light/dark. Read-only **CSV** `CSVTableView` (quote-aware
  `CSV.parse`, header row, zebra, monospaced, capped at 1000 rows).
- **Markdown editing:** pencil toggles a monospaced `TextEditor`; saves back to the `.md` on
  edit-exit / close / node-switch via `AppModel.saveFileContent` — one **undoable** file-write step
  (new `rawWrite`; `fileText` reads). CSV stays read-only this phase.
- **Entry points:** Space peeks the selected box (Esc closes) — wired in `handleKey`; a hover **⤢**
  chevron on note boxes; "Show Content" in both the canvas and sidebar context menus. *(Kept Shift-click
  free for the planned multi-select.)*
- **File-type awareness (Model):** `BoardNode.fileExt`/`fileType`; `name` strips the real extension;
  `rename` preserves it (fixes a latent .csv→.md bug). `syncFromDisk` now boxes `.md` + `.csv`
  (`AppModel.boxableExts`). Type-aware icons on canvas + sidebar. `peekId` state, pruned on delete.

**Verified:** `swift build` + `./build-app.sh debug` clean; launches & stays alive. Added demo
`Peek demo.md` + `sample.csv` to the test vault → sync **created a box for the .csv** (29 nodes; csv
present ✓). Ran the **CSV parser standalone** against the sample — quoted comma `"New York, NY"`
preserved (5×4) ✓. ⚠️ Couldn't screenshot the rendered peek (no screen-recording perm) — the *visuals*
(markdown layout, table styling, edit round-trip) need a manual eyeball: open the app, select **Peek
demo** → Space; select **sample.csv** → Space.

**Decisions / notes:** internal render only (no WYSIWYG); md editor is raw-text+preview toggle (not
live-styled) by design for v1; demo files are safe to Move-to-Trash in-app. Code-file boxes (.swift/
.json/etc.) intentionally *not* auto-added yet — only md/csv — to avoid flooding the canvas.

**Next up (Phase 2/3):** CSV cell editing + a dedicated code view; then **persistent in-place cards**
(the "open Notion on canvas" end state). Also: manual-verify S5 copy/paste keys.

**Quick verify:** `pkill -x GraphingApp; ./build-app.sh debug && open dist/GraphingApp.app` → select a
note → Space.

---

## 2026-06-21 — Session 5 — copy / cut / paste boxes (disk-aware, undoable)
**Ask:** "⌘C/⌘X/⌘V don't work — fix it in a smart way that fits the product."

**What changed (Model.swift):** added an internal, disk-aware clipboard.
- `ClipboardEntry` snapshots a top-level box + (for folders) its descendant boxes.
- `copyToClipboard()` / `cutToClipboard()` snapshot the selection (filtering to top-level roots;
  cut also marks `cutIds` so sources render dimmed). `canPaste` gates ⌘V.
- `paste(at:)` runs one `transaction`: **copy** → `tCopy`/`FileManager.copyItem` (recursive for
  folders) into a `uniqueRel(base: name + " copy")`, recreating board nodes for the duplicated
  subtree; **cut** → `tMove` the original(s) and reparent. Both **file into the folder under the
  cursor** (like drag-to-refile) and place boxes at the cursor, preserving the group's relative
  layout (centroid → paste point) with a 24pt cascade for repeat copy-pastes. New disk helpers
  `rawCopy`/`tCopy` (undo of a copy = trash the duplicate).

**What changed (Canvas.swift):** `handleKey` now maps ⌘C/⌘X/⌘V (via `charactersIgnoringModifiers`,
gated behind the existing "not editing / not in a text field" guard, so the rename field keeps native
clipboard). `pastePoint()`/`cursorWorld()` convert `NSEvent.mouseLocation` → world. `NodeView` dims
pending-cut sources (`opacity 0.45`).

**Current state:** `swift build` + `./build-app.sh debug` clean; launches & stays alive.
⚠️ **Couldn't keypress-test in this env** (no UI automation / screenshot) — logic mirrors the working
Delete handler and uses standard `copyItem`/`moveItem`; needs a 30-second manual check: select a box →
⌘C → ⌘V (expect a "… copy" file appears near cursor); ⌘X → hover a folder → ⌘V (expect it re-files);
⌘Z reverses both.

**Design notes / decisions:** internal clipboard only (no system pasteboard yet — so ⌘C here then ⌘V
in Finder/Obsidian won't carry; logged as a follow-up). Paste-target = folder under cursor, matching
the drag-to-refile mental model. Resolved the old "duplicate naming" open Q → `"… copy"` suffix.

**Next up:** manual-verify the above; then the big new idea under discussion — **inline file content
viewer/editor** (render .md/.csv in-box, "Expand" popover) — see BACKLOG "Inline file content" epic.

**Quick verify:** `pkill -x GraphingApp; ./build-app.sh debug && open dist/GraphingApp.app`

---

## 2026-06-21 — Session 4 — fix: blurry text when zoomed / enlarged (screen-space node rendering)
**Symptom (user):** "text loses quality when I make it bigger… as if it wasn't a font… loses quality
when I zoom in as well."

**Root cause:** `placed(_:)` applied `.scaleEffect(model.zoom)` to each `NodeView`. `scaleEffect` is a
layer/bitmap transform — glyphs were rendered once at base size, then the bitmap was stretched, so any
zoom > 1 (and large fonts viewed while zoomed) looked soft. Ironic given CLAUDE.md claimed "no global
scaleEffect."

**Fix:** removed the per-node `scaleEffect`; `NodeView` now renders in **screen space** via a `scale`
(= `model.zoom`) property — frame, fonts, padding, corner radii, shadows, strokes, dashes are all
`× scale`, so text is re-rasterized as crisp vector glyphs at every zoom level and font size. At
zoom = 1 the output is pixel-identical to before. Also converted the folder double-tap hit math from
scaled coords back to content units (÷ scale). Updated the CLAUDE.md Coordinates note with a ⚠️.

**Current state:** `swift build` + `./build-app.sh debug` clean; app launches and stays alive.
⚠️ Still can't screenshot in this env (screen-recording denied) — crispness unverified by eye but the
math is straightforward. Worth a 5-second manual zoom-in check.

**Watch-outs:** every node now re-lays-out text on zoom change (fine for this board's ~19 nodes; if the
board grows huge, profile pinch-zoom smoothness). Handles/resize/connectors were already screen-space
and untouched.

**Quick verify:** `pkill -x GraphingApp; ./build-app.sh debug && open dist/GraphingApp.app` → zoom in,
text should stay sharp.

---

## 2026-06-21 — Session 3 — resizable notes · light/dark theme toggle · "Huge" text tier
**Summary:** small follow-up polish after the user confirmed S2 "works pretty well." Three asks.

**What changed**
- **Resizable note boxes.** `ResizeHandle` now renders for *every* box kind (was folder-only); it
  picks `AppModel.noteMinSize` (110×52) vs `folderMinSize` by `node.kind`. Notes have no children so
  `effectiveFrame` returns the plain frame and `setFrame` drives the resize directly. Renamed the
  handle's MARK to "Corner resize handle (notes & folders)".
- **Light/dark theme toggle.** New persisted `AppModel.lightTheme` (`UserDefaults` key
  `gapp.lightTheme`), **seeded from the system appearance on first launch** so the toggle starts where
  the user already is. Applied via `.preferredColorScheme(...)` on `RootView` (covers Welcome + Main).
  Sun/moon button added to the `TopBar` (left of Close Vault). *Decision: simple Light⇄Dark toggle, no
  "follow system" option — user's choice.*
- **"Huge" text tier.** Added `case huge` (2.0×) to `TextSize`; auto-surfaces in the Color/Text-Size
  menus (canvas + sidebar) since they iterate `allCases`, and `from(scale:)` nearest-matches it.

**Current state:** `swift build` + `./build-app.sh debug` clean; app launches and stays alive against
the real old-format board. ⚠️ Could **not** screenshot to visually confirm (screen-recording
permission denied to the build process in this env) — resize-handle/theme/huge visuals are unverified
by eye; logic reviewed and sound. Worth a quick manual eyeball next session.

**Next up:** unchanged from S2 — finish ⭐ editable connectors (re-route endpoints + labels), remaining
connector styles (elbow/thickness/both-ended), empty-canvas right-click menu, **board-default text
size**; then Sprint 2 (marquee select · file-watching · ⌘Z-in-rename).

**Quick verify:** `pkill -x GraphingApp; ./build-app.sh debug && open dist/GraphingApp.app`

---

## 2026-06-21 — Session 2 — box color & text size · selectable/editable connectors · manual connect
**Summary:** knocked out the three user-starred audit items (⭐ folder color, ⭐ editable text size,
⭐ editable connectors) plus the connector-selection / right-click groundwork around them. Shipped in
four buildable increments (A: box color+size, B: edge selection, C: edge restyle, D: manual connect).

**What changed**
- **Box color & text size (notes + folders).** `BoardNode` gained optional `colorName` (a `BoxColor`
  raw value) and `fontScale`; helpers `accent` / `fontScaleValue`. New `BoxColor` (9-color palette) and
  `TextSize` (Small…XL) enums. Right-click a box → **Color** / **Text Size** submenus (apply to the
  whole multi-selection when the box is part of one; check-mark on the active size). Mirrored in the
  sidebar context menu. `NodeView` renders the accent on icon/border/folder-header/bg and scales titles.
- **Selectable, deletable connectors.** New `selectedEdge` state; tapping a line selects+highlights it,
  background tap / node select / create / navigate all clear it, Delete removes the selected edge first
  (else falls back to box deletion). The Canvas-drawn edges layer was replaced by one hit-testable
  `EdgeLine` view per edge (hit area = fattened stroked path) via a shared `edgeGeometry` helper.
- **Connector restyle.** Optional edge fields `colorName` / `directed` / `styleRaw` (+ `EdgeStyle`
  curved/straight). Right-click a connector → **Color**, **Style**, **Show/Hide Arrowhead**, **Delete**.
- **Manual connect (Miro "click adds, drag connects").** `HandleButton` now: *tap* = spawn same-kind
  sibling (unchanged); *drag* (≥6pt) = rubber-band a dashed connector onto another box to link them.
  Backed by transient `PendingConnect` state, a `pendingConnector` overlay with hover-target highlight,
  and `node(atWorld:)` topmost-box hit test. `connect()` de-dupes and focuses the new edge.

**Backward compat — empirically verified.** All new node/edge fields are `Optional`, so old
`board.json` decodes them as `nil`; the encoder omits nil keys (`encodeIfPresent`) so unedited boards
re-save byte-identical. Proven against the live vault `/Users/maxgomez/Documents/Graph test/`: its
board is *old-format* (19 nodes w/o `colorName`/`fontScale`, 5 edges w/o style keys) — the app launched,
stayed alive, and the round-trip wrote **no** spurious `null` keys.

**Current state:** `swift build` + `./build-app.sh debug` clean; launched against the real old board
and confirmed alive. No open build errors.

**Next up:** finish the ⭐ editable-connectors item — **re-route endpoints** (drag an edge end onto a
different box) and **connector labels**; remaining style controls (elbow, thickness, both-ended arrows);
empty-canvas right-click menu. Then back to Sprint 2 (marquee select · file-watching · ⌘Z-in-rename).

**Open questions to confirm with the user**
- Color palette: are the 9 named colors + "Default" the right set, or do they want a custom picker?
- Manual-connect gesture: drag-from-`+`-handle only, or also drag from the box edge itself?

**Quick verify:** `pkill -x GraphingApp; ./build-app.sh debug && open dist/GraphingApp.app`

---

## 2026-06-21 — Session 1 — setup → MVP → smoothness → folders/connectors → undo
**Summary:** built from nothing to a working, fairly polished MVP.

**What changed**
- Stood up the SwiftPM macOS app (Command-Line-Tools only, no Xcode); `build-app.sh` produces
  `dist/GraphingApp.app`.
- Core loop: choose a vault → create note/folder boxes that write real `.md` files / directories
  → sidebar tree ⇄ canvas ⇄ disk stay in sync.
- Miro `+` spawn handles (same-kind sibling + connector).
- Smoothness pass: two-finger scroll-pan + momentum, cursor-anchored pinch/⌘-scroll zoom, spring
  animations, grab cursor. (Fixed an early "boxes fly off" drag bug — `.global` gesture space.)
- Folders: auto-grow to fit contents, corner resize handles, group-move, drop-to-refile, nesting.
- Connectors: curved edge-to-edge with arrowheads (replaced ugly center-to-center lines).
- Full undo/redo reversing board **and** disk (trash↔restore, move↔move-back, create↔trash).
- Switched to `bypassPermissions`; wrote project docs (`CLAUDE.md`, `BACKLOG.md`, this file).

**Current state:** builds clean; last verified by launching `dist/GraphingApp.app`. No open build errors.

**Next up (Sprint 2):** marquee multi-select · live file-watching · fix ⌘Z-during-rename.

**Open questions to confirm with the user**
- Does two-finger scroll-pan feel correct on their machine? (sign is a one-line flip in the
  `CanvasView` `NSEvent` monitor if inverted).
- Connector arrowheads — keep always-on, or add a toggle?

**Quick verify:** `pkill -x GraphingApp; ./build-app.sh debug && open dist/GraphingApp.app`
