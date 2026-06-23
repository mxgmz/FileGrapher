# Spec — Folders Are Canvases (the "how")

> The implementation plan for `VISION-folder-canvas.md`. Grounded in the current code. The hard part is the
> coordinate migration (global → relative); the strategy is to **derive absolute from relative through one
> chokepoint** so we don't rewrite the ~115 position-reading call sites. Sequenced so the risky migration is
> *behavior-preserving and invisible* first, with a high-value low-risk win shipped before it.

---

## 0. The crux: one chokepoint, derive don't rewrite

Today every `BoardNode.x,y` is a **global** world center, read in ~115 places: **41 `effectiveFrame(of:)`
sites, 41 `.center` reads, 33 `worldToScreen/screenToWorld`** across Canvas/Model/App/FileContent/Sidebar/
VersionHistory. A naive "make coords relative" touches all of them — a rewrite that can't be shipped in
pieces.

The trick: **most world-position reads already go through `effectiveFrame(of:)`.** So we make the
relative→absolute derivation happen *inside* the derivation functions. Storage becomes relative; a node's
world position is **derived** by summing its ancestor chain; and `effectiveFrame` + a new `worldCenter(of:)`
become the single place that derivation lives. The 41 `effectiveFrame` callers don't change. Only the
direct `.center` world-readers and the *write* paths need touching.

> **Net rule:** nothing outside the derivation functions and the write paths is allowed to treat `node.x,y`
> as world coordinates after the migration. `node.x,y` means *"relative to my parent folder"*; ask
> `worldCenter(of:)` for absolute.

---

## 1. Storage change + the one-time migration

- `BoardNode.x,y` is reinterpreted as **the center relative to the parent folder's anchor** (a folder's
  anchor = its own stored center). Root-level nodes are relative to world origin → their values are
  unchanged, so the root canvas looks identical day one.
- **`BoardData.version` 1 → 2.** On load, if `version < 2`, run the one-time transform:
  1. Snapshot every node's *original* global center.
  2. For each node N with parent folder F: `N.stored = originalGlobal(N) − originalGlobal(F)`. Root nodes:
     `N.stored = originalGlobal(N)`.
  3. Set `version = 2`, save.
  Using the snapshot (not freshly-written values) keeps it correct under nesting. Lossless and reversible —
  deriving back reproduces the original globals exactly. **This is the ponytail self-check:** a headless test
  that migrates a fixture board then asserts `worldCenter(of:) == originalGlobal` for every node.

---

## 2. The derivation chokepoint

```
// world center = my relative center + my parent folder's world center, recursing to root.
func worldCenter(of node) -> CGPoint        // node.center + worldOrigin(of: parentFolder(node))
func worldOrigin(of folder) -> CGPoint      // worldCenter(of: folder)  (a folder's anchor is its center)
func worldFrame(of node) -> CGRect          // built on worldCenter; replaces today's node.frame for reads
```

- Walks the `parentRel` chain (already how the tree is known). **Cache** the per-node world point, keyed to
  a board-revision counter bumped on any position/structure change — the same pattern `effectiveFrame`
  already needs to avoid recomputing the recursive auto-grow every frame.
- `effectiveFrame(of:)` is re-pointed onto `worldFrame`. The 41 callers are untouched.

---

## 3. What gets *simpler*, what changes

- **`moveSubtree` becomes trivial — and mostly disappears.** Moving a folder no longer prefix-shifts every
  descendant's coords; you change the folder's own (relative) center and the children move *because they're
  derived through it*. Re-anchoring whole subtrees, the stranded-child repair, the runaway-coordinate
  meltdown class — all dissolve, because children were never in global space to strand.
- **Re-parenting (drop a box into another folder)** is the one write that converts:
  `newRelative = worldCenter(node) − worldOrigin(newFolder)` so it lands where the cursor is, then stores
  relative. (`move(_:intoDir:)` already does the disk re-file; this is the coordinate half.)
- **Drags stay simple:** a drag is a pure translation, so the world delta *is* the local delta — add it to
  `node.x,y` unchanged. No conversion.
- **Auto-grow is retired (Phase 2, not Phase 1).** Eventually a folder's footprint = its stored **card
  size**, and children live in the folder's own (possibly larger, scrollable) canvas — not "the folder
  swells to enclose scattered kids." See §6 for why this is deferred.

---

## 4. Edge promotion — ships FIRST (independent of the migration)

This is render-layer only and needs nothing from the coordinate migration — it works on today's global
coords + the existing `collapsed` flag. So it ships first: immediate value, low risk, de-risks the project
by delivering the recordentaln8n architecture-graph payoff before the scary refactor.

For each `BoardEdge`, at draw time:

1. **Promote each endpoint** to its **nearest visible ancestor**: walk up `parentRel`; if an ancestor folder
   is collapsed, the visible endpoint becomes that folder (recurse upward to the topmost collapsed ancestor).
2. **Drop internal edges:** if both endpoints promote to the *same* visible node, the link is internal — draw
   nothing (optionally a small "has internal links" dot on the chip).
3. **Aggregate:** group surviving edges by their `(visibleFrom, visibleTo)` pair; draw **one** edge per pair,
   weighted (thickness / count label) by how many real links it represents. Direction preserved.

Pure function over `(nodes, edges, collapse-state)` → `[(from, to, weight)]`. **Ponytail self-check:** a
headless test on a nested fixture asserting promotion + aggregation + internal-hiding. Drilling (hover an
aggregated edge to reveal the real links) is a later nicety.

---

## 5. The write paths (audit list)

The only places that must learn "store relative": `endDrag`/`dragGroup` (delta unchanged), `move(_:intoDir:)`
re-parent (convert), `addNote`/`addFolder`/`addChildNote`/`spawnCenter` (place in the parent's local space),
`arrangeRadial` + `resolveOverlaps` (operate in one folder's local space — which is *more* correct than
today), and the MCP `canvas_arrange`/`canvas_move`/`canvas_get`/`renderBoardPNG` (become altitude-aware:
positions are relative; `canvas_get` reports both relative and derived world). Everything else reads through
§2.

---

## 6. Phasing (risk-ordered, each shippable)

1. **Edge promotion** *(ships first — §4).* Render-only, no migration. Win: the living-canvas graph reads as
   a folder-level architecture map at every altitude. Validates on recordentaln8n.
2. **Relative-coordinate migration — *invisible***. The §1 storage swap + §2 chokepoint + §3/§5 write paths,
   **keeping auto-grow temporarily** so the canvas looks pixel-identical. Done when: migrated board renders
   identically, `moveSubtree` simplifies, and **dragging/duplicating a folder carries its layout** (the
   portability win). The scary phase, made boring: behavior-preserving, headlessly round-trip-tested.
3. **Folder-as-card rendering.** Retire auto-grow; a folder is its **card** (a bounded, scroll/zoom viewport
   onto its own relative canvas). Chip → card → entered along the zoom axis. The expandable folder-note card
   already exists to build on.
4. **Expansion: memory + levels + learned.** Per-folder view state (expanded set + pan/zoom, stored on the
   folder); the title → preview → full **spectrum** (a small enum on the node); **learned** pre-expansion
   from open-counts in the app memory system. (No prescriptive auto-expand — per the vision.)

The cartographer MCP tools become altitude-aware across phases 2–3 and gain reach: `canvas_arrange` now lays
out *within a folder's own canvas*, which is exactly the recursive structure the cartographer's "altitude"
needs.

---

## 7. Open questions parked

- **Folder anchor = center vs top-left.** Center is simplest (we have `node.center`); top-left may read
  cleaner for a "canvas origin." Pick at Phase 2 when cards get a real viewport.
- **One `board.json` (relative) vs a sidecar per folder.** Per-folder sidecars make a *directory* physically
  portable (copy the folder, layout travels); one board.json is simpler but doesn't travel with a `cp`.
  Decide before Phase 2 — it changes where relative coords are stored.
- **Cache invalidation granularity** for `worldCenter` — per-revision global bump is the lazy version;
  per-subtree only if profiling on a big vault demands it.
- **Edge-promotion cost** at thousands of edges — memoize the promotion map per collapse-state, not per
  frame.
- **`canvas_get` payload** in the relative world — report relative coords + a derived world box, or make the
  agent altitude-scoped so it never sees the whole tree at once.
