# Vision — Folders Are Canvases

> Captured from the 2026-06-23 brainstorm (Max + Claude). The structural foundation under "proper folder
> organization" and "smart expansion" — and the thing that makes the cartographer's *altitude* real instead
> of faked. **No code here** — the model, the laws, the migration it implies. Prerequisite to be built
> *before* deeper folder/expansion work. Siblings: `VISION-living-canvas.md`, `VISION-agent-cartographer.md`.

---

## 0. The thesis (the one idea underneath everything)

The app holds three axioms already: a box *is* a file, a folder *is* a directory, a connector *is* a real
link. This adds the spatial one:

> **A folder *is* its own canvas.** Its children's coordinates are **relative to it**, not global.

That makes "folder = directory" total — not just about *identity*, but about *space*. The **canvas tree
becomes the disk tree**: every directory is an infinite canvas, and a note's position lives *inside* its
folder. Move a folder, duplicate it, drop it into another vault — its whole arrangement travels with it,
because the arrangement was never in global space to begin with.

**Why now (the proof):** one global coordinate space does not scale. Opening the real `recordentaln8n`
project produced a **52,000px-tall sprawl** of 364 boxes, folders ballooning to enclose scattered children,
half the screen empty. The single infinite canvas is the bottleneck. **Nested canvases = an infinite canvas
at every level = scales fractally.** The "infinite canvas" identity isn't lost; it becomes recursive.

**Why it's the prerequisite:** today *expand* fights the global layout — we watched the Japan-Trip folder
*balloon* and recordentaln8n sprawl, because expansion grows `effectiveFrame` into one shared space (it
violates the cartographer's own *minimal-motion* law). You can't build good expansion on top of that. Make a
folder self-contained first, and expansion stops being "inflate the global space" and becomes "show / enter
a bounded place." Max's ordering instinct is correct: **this, then folder-organization + expansion.**

---

## 1. Decisions locked this session

| Topic | Decision |
|---|---|
| Coordinate model | **Relative per folder.** A child's `x,y` is relative to its folder's canvas origin; migrate `board.json` from global → per-folder coords |
| Folder = unit | **Fully portable** — move/duplicate/share a folder and the exact layout travels with it |
| Interaction | **Open in place as a card sized to its content** (a card can be as big as it needs — a bounded, scrollable/zoomable window into the folder's own canvas); collapsed = a chip |
| Navigation | **Altitude / zoom** — zoom out → folders are chips/nodes; zoom into one → it unfolds into its own canvas |
| Connections | **Always shown, via edge promotion** to the nearest visible ancestor; **aggregate** parallel cross-boundary edges; **hide** fully-internal ones |
| Expansion memory | **Per-folder view is remembered** (what's expanded + pan/zoom), restored on return |
| Expansion intelligence | **Learned from habits** (pre-expand the files you actually open) — *not* a prescriptive auto-expand-on-entry heuristic |
| Expansion granularity | **A spectrum** — title → preview (first lines) → full — not a binary |

---

## 2. The coordinate model — relative space per folder

- A node stores its position **relative to its parent folder's canvas**. The root vault is just the
  top-level canvas. Absolute world position is *derived* by walking up the tree (sum of ancestor offsets),
  only when needed for rendering at a given altitude.
- **Moving a folder is free:** you change the folder's own position in *its parent's* canvas; nothing inside
  changes, because nothing inside was ever expressed in global terms.
- This **replaces `effectiveFrame`'s job.** Today a folder's frame is reverse-engineered from where its
  children landed in global space (auto-grow union). In the new model, a folder *owns* a bounded canvas; its
  card size is its own property (a viewport), and children live in its relative space. Auto-grow becomes
  "the folder's canvas is infinite; the card is a window onto it," not "the folder swells to chase its kids."
- **Migration (one-time):** for each existing node, `relative = global − originOf(parentFolder)`, walking
  the tree leaf-up. Define a folder's **origin** (top-left of its canvas, or its header anchor) and convert
  once on load, versioned in `board.json`.

---

## 3. Interaction — chip, card, or canvas (one continuous zoom)

A folder has three states along a single zoom axis:

1. **Chip (collapsed):** a header + count + its promoted/aggregated connections. The navigable overview.
2. **Card (expanded in place):** a bounded window showing the folder's own canvas, **sized to its content**
   — it can be large, and you scroll/zoom *within* it. It sits among its siblings without disrupting their
   layout (the card has a size in the parent; its interior is its own space).
3. **Entered (full):** zoom all the way in and the folder's canvas fills the view — you're working *inside*
   it, with the same gestures, recursively.

The law that keeps this sane: **a folder never sprawls its parent.** Whatever happens inside a folder's
canvas is bounded by its card/viewport. Collapse-by-default + self-containment is what kills the global
sprawl for good.

---

## 4. Connections — edge promotion (the graph reads at every altitude)

The rule (Max's): a connection is **never hidden**. If an endpoint sits inside a collapsed folder, the edge
**re-anchors to the nearest visible ancestor**, bubbling up recursively until it reaches something on
screen. Expand a folder → the endpoint descends toward the real note; collapse → it floats back up to the
chip. This is the standard *edge-promotion* move from nested-graph editors, and it's what makes the
nested-canvas model and the living-canvas link graph coexist.

Two refinements the rule forces (so the collapsed view isn't a hairball):

- **Aggregate parallel edges.** N links between two collapsed folders draw as **one** edge between the two
  chips, **weighted** (thicker / labeled with the count) by how many real links it stands for.
- **Hide fully-internal edges.** If both endpoints bubble to the *same* visible ancestor, the link is
  internal — don't draw a loop on the chip (at most a small "has internal links" marker).

**The payoff:** collapsed folders stop being dumb chips and become **nodes in a higher-level architecture
graph**. Collapsed to the top level, recordentaln8n would *show* "tools ↔ supabase coupled," "docs ↔
n8nworkflows tightly linked" — a dependency map that emerges from the real `[[links]]`, at whatever altitude
you're standing. The living-canvas graph finally pays off at scale. (Drilling: hover/click a promoted or
aggregated edge to trace it down to the underlying real connections.)

---

## 5. Expansion — remembered, learned, graduated

Folder-as-canvas hands us expansion memory almost for free, then intelligence layers on:

- **Per-folder view memory.** Each folder-canvas remembers its own state — which boxes are expanded, the
  pan/zoom. Return to a folder and it's how you left it. This *is* the "memory for expansion."
- **Learned habits.** The vault remembers which files you actually open and **pre-expands them** over time —
  it learns *your* "loud" boxes. Uses the app's memory system. (Deliberately **not** a prescriptive
  auto-expand-on-entry heuristic — the smarts come from your behavior, so the experience stays yours.)
- **A spectrum, not a switch.** Expansion graduates: **title → preview (first lines) → full card**, with a
  smart default per file type and importance. "Expand" stops being all-or-nothing.

---

## 6. The design laws

If a feature breaks one, it's probably wrong:

1. **The canvas tree is the disk tree.** Every folder is a coordinate space; a child's position is relative
   to its folder, never global. Moves, duplicates, and shares of a folder are therefore free and lossless.
2. **A folder never sprawls its parent.** Collapsed = chip; expanded = a bounded card; entered = its own
   view. The parent's layout is never disrupted by what lives inside a child. (Minimal-motion, finally
   structurally enforceable.)
3. **Connections never hide — they promote.** Nearest-visible-ancestor re-anchoring + aggregation +
   internal-hiding. The graph is legible at every altitude.
4. **Expansion is remembered, not recomputed**, and its intelligence is **learned from you**, not imposed.
5. **Expansion is a spectrum, not a binary.**
6. **Altitude is the primary navigation** — one continuous zoom from whole-vault → folder → a single note.

---

## 7. How it relates to the other visions

- **Living Canvas** (`VISION-living-canvas.md`): connections are real `[[links]]`. Edge promotion is what
  lets that link graph stay readable once the canvas is nested — the read-side auto-draw now resolves to the
  nearest visible ancestor.
- **Agent Cartographer** (`VISION-agent-cartographer.md`): "the map has altitude" was the aspiration;
  folder-as-canvas is its *structure*. The MCP tools become altitude-aware — `canvas_arrange`/`move`/`get`/
  `screenshot` operate **within a folder's canvas**, and the cartographer organizes each folder's space
  independently (top level = folders-as-nodes; drill in = each folder's own radial/grid). Today's tools
  already proved the loop on the flat model; this gives them the recursive structure to scale.

---

## 8. The whole thing, in one breath

Every folder is its own infinite canvas in **relative** space, so a folder is a **portable unit** you move
and the layout travels; you navigate by **zoom** (chip → bounded card → entered canvas); connections are
**never hidden** but **promote** to the nearest visible ancestor and **aggregate**, so the link graph reads
as an architecture map at every altitude; and expansion is **remembered per folder, learned from your
habits, and graduated** title → preview → full. The canvas tree finally *is* the disk tree.

---

## 9. Open questions parked for later

- **Migration mechanics:** the leaf-up global→relative transform, the definition of a folder's canvas
  **origin**, and the `board.json` version bump. One-time, on load, must be lossless and reversible.
- **One board.json with relative coords, or a board sidecar per folder?** Per-folder sidecars make a folder
  *physically* portable (drop the directory anywhere, layout included) but multiply files; one relative
  board.json is simpler but doesn't travel with a copied directory. Decide when we do the migration.
- **Edge-promotion performance:** nearest-visible-ancestor per edge can't recompute every frame on a big
  graph — needs caching keyed to the collapse/expand state.
- **Aggregated-edge semantics:** weight by count? thickness scale, label, or both? hover-to-expand into the
  real links.
- **Nested expanded cards:** "a card as big as its size" composing several levels deep — where's the limit
  before scroll-within-card beats zoom-into, and vice versa?
- **Learned expansion signal:** open count, recency, dwell time? And how it surfaces (pre-expand vs suggest).
- **Cross-vault portability** of a folder unit (ties to the sidecar question).
