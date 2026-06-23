# Design — Interaction Polish (the frame model, collision & pin)

> Brainstormed with Max 2026-06-23. **Design only — no code yet.** This is the *what & why*; the
> *what-to-build* (tickets, files, risks, verification) lives in `BACKLOG.md` → "Sprint 5". Design law,
> inherited from the living-canvas spec: **"alive but sober."** Affordances are calm, predictable, and
> never fire by accident ("no funny business").

---

## 0. The root problem

Everything on the canvas is "a box with a `.contentShape(Rectangle())` over its full `effectiveFrame`"
(`NodeView`, `Canvas.swift`). But there are **two different objects** wearing the same hit behavior:

- A **note** is a *card* — solid, the whole rectangle is live.
- A **folder** is a *frame/container* — a labelled region that *holds* cards. Almost all of its
  rectangle is empty space that belongs to its children.

Because a folder's hitbox is its **auto-grown union frame** (`effectiveFrame` = header + all children +
padding, `Model.swift:1241`), a folder silently owns a huge invisible rectangle whose size *changes as
you edit*. That is the source of most of the "funny business": you can't rubber-band notes inside a
folder, the empty interior eats clicks/drags, and what's clickable shifts under you. Fixing the mental
model first makes everything else fall out.

---

## 1. 🔒 LOCKED DECISION — **Folder = frame** (2026-06-23)

A folder is a **container, not a card.** Its hit behavior splits by region:

| Region | What's live | Gesture |
|---|---|---|
| **Header bar** (the 40px title strip) | identity, drag handle, `+`, disclosure ▸, ⤢ | **drag = move** the folder (+ its contents); click = select; the `+` adds a child note |
| **Border ring** (~8px inside the frame edge) | resize affordance / selection outline | corner/edge **resize**; click = select |
| **Interior** (everything else) | a **drop zone**, otherwise pass-through | **drag = marquee** the children inside; click = select folder; **double-click = new note here** (unchanged) |

Consequences (all intended):
- **Marquee works inside a folder** — dragging the empty interior rubber-bands its children instead of
  moving the folder. This is the headline win.
- **The folder no longer "swallows" the canvas** — its interior is for its children and for filing, not
  a giant click target.
- **Notes still render above folders** (`world` ZStack draws folders first, notes second) so a child
  note is always clickable on top of its parent.
- **Move the folder = drag its header.** (Today the whole frame drags it.)

A **note** keeps the current behavior: the whole card is live (drag/select/double-click-rename).

> Why locked: every other Sprint-5 item (marquee-in-folder, collapse, expand-to-note, clean collision)
> depends on the folder being a frame. Decide once, build on it.

---

## 2. 🔒 LOCKED DECISION — **Nothing overlaps: a drop pushes; a pin anchors**

Product choice: this is a *tidy* canvas, not a free-for-all. Sibling boxes never end up stacked.

**Push (replaces today's snap-away).** Today `endDrag` calls `nearestFreeCenter` (`Model.swift:1200`),
which moves the *dropped* box to the nearest free spot — the box you placed jumps away from where you
let go. New behavior: **the dropped box stays where you put it, and overlapped siblings are pushed
aside** along the minimum-translation vector, cascading to their neighbors, until no two siblings'
hitboxes intersect.

**Pin (the anchor).** A box can be **pinned** (`BoardNode.pinned`). A pinned box:
- **can't be dragged** (drag is a no-op; cursor shows a lock), and
- **is never pushed** — it's an immovable obstacle the push routes *around*.

If a push has nowhere to go (e.g. boxed in by pinned siblings), it falls back to today's
`nearestFreeCenter` for the *mover* (snap the dropped box to the nearest gap) so we never deadlock.

**Scope rules (carried from the old WS3 plan — still correct):**
- **Siblings only** — same `parentRel`. A folder *must* contain its children, so parent↔child never
  "collides"; only sibling-vs-sibling overlap is illegal.
- **Hitbox = `effectiveFrame`** (AABB); overlap = `rect.intersects`. n² is nothing at this scale.
- **Never enforce on load.** Existing boards overlap; a global "settle" would yank Max's layout. Only
  *new* moves / resizes / expansions resolve. (Same rule that makes this safe to ship.)
- **One undo step.** The whole push rides the drag's existing `commit(before:after:)` snapshot in
  `endDrag` — sibling moves made before the commit are captured automatically; no new undo plumbing.

**🔒 Locked (2026-06-23):** **push-on-drop** — siblings resolve when you let go, not every frame. Calm,
deterministic, cheap, and sidesteps the folder-auto-grow jitter that live push would hit. (Live push is
explicitly a *later, optional* polish — not this sprint.)

---

## 3. Folders are **collapsible** *and* **expandable** (two different axes)

These point in opposite directions; keep the affordances distinct so they never confuse.

- **Collapse (hide children)** — a disclosure ▸ in the header hides the folder's children on the canvas
  and shrinks the frame to **just the header + an "N items" count badge**. A dense board becomes
  navigable. Children stay in `board.json` (not deleted) — they're just not rendered/hit-tested while
  collapsed. `BoardNode.collapsed`.
- **Expand (open the folder-note)** — the same ⤢ a note has, now on folders: open an editable content
  card for the folder's **folder-note** (Obsidian convention: a `<FolderName>.md` *inside* the folder).
  Created lazily on first edit; never spuriously. Reuses the note card machinery.
- **Empty-folder hint** — an empty folder shows a faint "double-click or drag notes here" so it doesn't
  read as broken.

**🔒 Locked (2026-06-23):** folder-note filename = **`<FolderName>.md` inside the folder** (the Obsidian
folder-note convention). Created lazily on first edit; never spuriously.

---

## 4. Cards: same hitbox grammar, and expanding pushes

An expanded card is just a note with a bigger `effectiveFrame`, so it participates in the **same**
collision system as everything else — with one hook: **expanding a card pushes its neighbors** to make
room (today `setExpanded` grows the box in place and can overlap, `Model.swift:1840`). Card size is
**remembered across collapse** (`BoardNode.cardSize`) instead of snapping back to the default each time.

---

## 5. The eight workstreams (summary — full detail in BACKLOG "Sprint 5")

| # | Workstream | Core of it | Risk |
|---|---|---|---|
| **T1** | Hover & cursor feedback | outline the exact hitbox on hover; per-region `NSCursor` (grab/resize/crosshair/pointer) | low |
| **T2** | **Folder = frame** hitbox | header+border live, interior = marquee/drop (the §1 lock) | **high** (hit-testing) |
| **T3** | Selected-box chrome | clamp handle sizes to screen px; hide chrome below a zoom; thin the four `+` | low |
| **T4** | **Push + Pin** collision | push siblings on drop; `pinned` immovable obstacle (the §2 lock) | med-high |
| **T5** | Folder collapse + empty hint | disclosure ▸ hides children + count badge (resize-no-rescale already built) | med |
| **T6** | Expandable folders + card polish | folder-note card; remembered `cardSize`; header-double-click rename | med |
| **T7** | Connector polish | draggable endpoints (re-route + link rewrite), labels, hover hit-zone | med |
| **T8** | Micro-polish & consistency | radii/strokes/shadows family; animation vocab; empty-canvas hint | low |

**Build order (dependency + blast radius):** T1 → **T2** → T3 → **T4** → T5 → T6 → T7 → T8.
T1/T3/T8 are quick perceived-quality wins; T2 is the keystone (do it carefully, early); T4 is the
central new behavior; T5/T6 sit on top of T2; T7 is independent and lowest priority.

---

## 6. Already built — do **not** rebuild

- **Soft-snap on drop** (`nearestFreeCenter`, `endDrag`) — exists; T4 **replaces** its role (snap→push)
  but keeps it as the no-room fallback.
- **Folder frame-resize without rescaling children** (`resizedFrame` + `contentsBounds`,
  `Model.swift:1931`) — done. T5 only adds *collapse* + the empty hint, not resize.
- **Drop-target highlight** (`dropTargetId` / `dropTargetOutline`) — exists; extend (not replace) for the
  filing tint.
- **Marquee, ⌘A, shift-click, group-move** — exist; T2 only changes *where a drag starts* over a folder.

---

## 7. Cross-cutting engineering rules (so nothing breaks)

These are the invariants every ticket must respect — they're why the existing app is stable:

- **All geometry mutations go through the undo engine** — `transaction {}` or
  `beginInteraction()`→`endInteraction()`/`endDrag()`. Never write `board.nodes[i]` outside one, or
  undo/redo + disk desync. Push needs **no** new undo plumbing (it rides the drag's commit snapshot).
- **Clamp every computed coordinate/size** with `clampCoord`/`clampSize` (the S10 meltdown guard — a
  runaway coord pins WindowServer at 100% CPU). The push solver and collapse must reuse them.
- **New `BoardNode` fields are `Codable`-optional** (`pinned`, `collapsed`, `cardSize`) so old
  `board.json` decodes byte-compatibly (the established pattern: `expanded`, `fileId`, `colorName`).
- **`effectiveFrame` is hot** — it runs every render and recurses through nested folders (with a
  cycle/depth guard). Collapse must **short-circuit** it (a collapsed folder returns its header frame,
  no child recursion); the push solver must **cap** its cascade (bounded ring/iteration count, accept
  "good enough") so it can never spin.
- **Render in screen space (× zoom); never `.scaleEffect` a node** (blurs text). Chrome that scales
  (T3) clamps to a screen-pixel range; it does not bitmap-scale.
- **Collapsed (hidden) nodes stay in `board.json`** and in `dragGroup`/`delete`/`syncFromDisk`; they're
  excluded only from *render*, *hit-test*, and *marquee*. Edges to a hidden child hide with it.
- **Folder auto-grow makes hitboxes dynamic** — pushing a child re-grows the folder, which can re-collide
  with the folder's own siblings. Resolve **child-level first, then folder-level**, both capped; accept a
  residual rather than loop.
- **Headless-test the pure geometry** (push solver, collapse `effectiveFrame`, pin-as-obstacle) the way
  `nearestFreeCenter`/`ManagedLinks` are tested — concatenate + assert, no framework. UI bits get Max's
  visual pass (the env can now drive the UI via the S19 recipe; still verify logic headlessly too).
- **Verify per ticket:** `./build-app.sh debug` clean + app launches 0% CPU + the ticket's manual pass,
  before moving on. Update `HANDOFF.md` + tick `BACKLOG.md`.

---

## 8. 🔒 Locked decisions (2026-06-23)

All four resolved before coding — no open forks remain for Sprint 5:

1. **T4 — push timing:** **on-drop** (not live during drag). Live push is a later, optional polish only.
2. **T6 — folder-note filename:** **`<FolderName>.md` inside the folder** (Obsidian convention), created
   lazily on first edit.
3. **T2 — folder-interior click (not drag):** **selects the folder**. (Drag = marquee its children;
   double-click = new note; header drag = move.)
4. **T3 — chrome-hide zoom threshold:** **~0.5×** — below it, hide the `+`/resize selection chrome (keep
   the selection outline).
