# Vision — The Living Canvas

> Captured from the 2026-06-21 brainstorm (Max + Claude). This is the product/UX/architecture spec for
> the next era of the app. **No code here** — principles, formats, models, and the phased rollout.
> Source of truth for *what we're building and why*; `BACKLOG.md` tracks the *when*.

---

## 0. The thesis (the one idea underneath everything)

The app already holds two axioms:
- **A box *is* a real file.**
- **A folder box *is* a real directory.**

The Living Canvas adds a third:
- **A connector *is* a real link inside the file.**

That collapses the canvas and the vault into **two views of one living graph**. You can edit the graph
**spatially** (draw an edge) or **textually** (type `[[X]]` in Obsidian / have an agent write it), and
it's the same underlying truth. The product is therefore not a diagram tool — it's:

> **A spatial, real-time, agent-collaborative front-end to a plain-markdown brain (and codebase).**

Everything below is just answering: *where does the link physically live, in which direction, and how
does the graph stay alive and safe while you and an agent both touch it.*

---

## 1. Decisions locked in this session

| Topic | Decision |
|---|---|
| Where links physically live | **Managed `<!-- canvas-links -->` block** in the `.md` (human-visible, Obsidian-clickable, app round-trips it) |
| Connection authoring | **Manually drawable** (draw an edge → link is written). Notes authored as `[[wikilinks]]`; code via comment-annotation; folders via folder-notes |
| Edge styling | Lives in `board.json` as a thin **decoration layer** keyed to `(from → to)`. Lose it → lose styling, never the link |
| Default conflict policy | **Reload** (non-destructive) — *plus* the ghost overlay as the cool-but-safe path |
| Live overwrite | Done as **live-preview-then-commit** via the ghost overlay (never blind-clobber) |
| The loupe | **Local lens** — a draggable "flashlight" you point at part of the canvas to see the diff |
| Live mode feel | **Ambient** (quiet, subtle), not red/green everywhere |
| Live ghosts | **Opt-in** |
| Concurrency: non-overlapping edits | **Let them flow live** (blocks you aren't touching update in real time) |
| Concurrency: the block you're in | **Soft-lock** — block-scoped, **symmetric** (agent can hold it too; you see its presence) |
| Guiding aesthetic | **"Alive but sober."** |

---

## 2. "Alive but sober" — the design laws

The aesthetic, turned into constraints so it actually governs decisions (if a feature breaks one, it's
probably wrong):

1. **Motion implies meaning.** Things move only when something real changed — always one gentle spring,
   never a flash or a blink. If it pulses, it earned it.
2. **Color is expensive.** Green/red is reserved for the **loupe** and **real conflicts**. Live flow uses
   a single **quiet tint that fades** — you sense the change, you're not assaulted by a diff.
3. **Presence is a whisper.** A halo and a fading block-highlight. No avatar parade, no chat bubbles.
4. **Calm is the default; intensity is reached for.** Ambient and quiet unless you pick up the loupe or
   opt into ghosts. The app never escalates on its own — *except* the one forced conflict ghost, because
   that's a decision only you can make.

---

## 3. Feature 1 — Connections are real links

### 3.1 Source of truth
- **Existence of a connection = a real `[[wikilink]]` in the file.** That's the truth: Obsidian sees it,
  an agent sees it, it survives even if `board.json` is deleted.
- **The look of a connection** (color, curve, arrowhead, label) = a thin **decoration layer in
  `board.json`**, keyed to the `(from → to)` pair. Lose it and you lose styling, never the actual link.
- This flips today's `BoardEdge` ("diagram only — not on disk") into "the edge is on disk; only its
  costume is in board.json."

### 3.2 Where the link physically lives — a managed block
Not inline in prose (too messy). A **managed block** the app owns and round-trips, fenced by markers so it
never touches what you wrote:

```
<!-- canvas-links -->
- [[Target Note]] — references
- [[Other Note]]
<!-- /canvas-links -->
```

- Human-visible, clickable in Obsidian, regenerable without clobbering your text.
- The app **only rewrites between the markers** — edits elsewhere (yours, Obsidian's, an agent's) are safe.
- *Optional robustness:* also mirror the canonical list into **YAML frontmatter** so machines have a clean
  parse target and humans get the pretty version.
- Drawing an edge inserts a line here; deleting removes it; **the existing paired board+disk undo engine
  reverses both in one step** (this feature is a perfect fit for machinery we already have).

### 3.3 Directionality
A wikilink is inherently directional (A contains `[[B]]` → arrow A→B; B gets a backlink for free). So a
**directed edge = a link in the source file**, and the canvas arrow literally mirrors *which file contains
the link.* Honest and self-consistent.

### 3.4 Typed / labeled connections (lean past Obsidian)
Let an edge carry a **relationship type** — `references`, `depends on`, `see also`, `contradicts`. Stored
as the suffix in the managed block (`- [[B]] — depends on`) or a Dataview inline field
(`depends_on:: [[B]]`). Now the canvas isn't a mind-map — it's a way to **author a typed knowledge graph
that's still plain markdown.** Differentiated, and nearly free structurally.

### 3.5 Code references — *derive*, and allow manual
You can't write `[[Other]]` into a `.swift` file without breaking the build, so split by file type:

- **note ↔ note:** authored `[[wikilinks]]` (managed block). Bidirectional with Obsidian.
- **code ↔ code:** **discovered** — parse imports / symbol references and auto-draw those edges
  (read-only, recomputed when files change). For **manual** code links, store a **comment annotation**
  (`// @link Other.swift` / `// @see Other.swift`) that survives compilation and is machine-parseable.
- **note ↔ code:** the note links to the code (`[[code-demo.swift]]` / a path); code can't link back
  inline, so it's one-way and shows as a **backlink** on the code box.

Principle: **notes are *authored*, code is *observed*** (plus optional comment-annotations). Same canvas,
two truth-sources.

### 3.6 Folders — give them a "folder note"
Directories have no body to hold a link, so adopt the Obsidian **folder-note** convention: a folder's
identity is an index file inside it (`FolderName/FolderName.md` or `index.md`). Connecting a folder writes
the link into that note (auto-creating it if missing). **Bonus:** folders gain real, previewable content.

### 3.7 The "automatic" UX
- **Connecting is the gesture; the link-write is a silent side effect.** No dialog. Draw → it appears in
  both the canvas and the file instantly. Undo reverses both.
- **Reading is symmetric:** a file with `[[links]]` (written in Obsidian or by an agent) **auto-draws the
  edges**, so the canvas always reflects the true link graph. (This is the bridge into Feature 2.)

---

## 4. Feature 2 — Live updates

File-watching (FSEvents/DispatchSource on the vault root, debounced) becomes the **read side** of the
bidirectional graph — not just a convenience refresh.

**What updates live:**
- **Links** — an agent/Obsidian adds `[[X]]` → the edge **animates into existence.** *Watch an agent wire
  up your vault* — the demo moment.
- **Content** — a watched file changes → expanded cards re-read and update.
- **Structure** — new/deleted/moved files → boxes fade in / fade out / glide to their new folder.

**The three make-or-break UX problems:**
1. **Edit conflicts.** Never silently clobber in-progress edits (see §6).
2. **Where new boxes land.** Live arrivals must not scatter the layout — stage them in a soft "inbox" lane
   or near their folder, **never on top of existing work.**
3. **The self-write feedback loop.** When *the app* writes (a link, an accepted ghost), the watcher fires
   too — must distinguish self-writes from external writes or it loops/janks. *Same class of feedback loop
   that caused the S10 coordinate meltdown.* Solve with a self-write suppression window / write-token.

---

## 5. Feature 3 — The ghost overlay & time-travel

### 5.1 The "aha": the overlay is how live-overwrite becomes safe
> Incoming changes never overwrite your work — they **arrive as a translucent ghost** you can see, then
> accept or dismiss.

Live-overwrite becomes **live-preview-then-commit**. The same visual grammar serves both the
conflict-safety case *and* time-travel — so they're really one feature in two hats.

### 5.2 Three diff axes (green/red means three different things)
1. **Content diff** — text changed → green/red lines *inside the expanded card.*
2. **Structure diff** — files/folders added/deleted/moved → boxes **fade in green**, **fade out red**, or
   **glide.**
3. **Link diff** — a `[[link]]` appeared/was cut → **edges draw in green / dissolve in red.**

A complete overlay speaks all three.

### 5.3 The structural key: the canvas is a stable stage; history flows through it
`board.json` layout isn't in git, so "go to commit X" can't restore old positions — that data doesn't
exist. Resolution: **positions don't time-travel; content, files, and links do.** A fixed map where the
actors change costumes. Files that didn't exist (or were deleted) ghost in near their old neighbors or in
a thin **"removed" gutter.**

### 5.4 The loupe (local lens)
A **draggable "flashlight"** you point at part of the canvas: under it you see the ghost diff, outside it
the clean live view. Also solves performance — only render diff under the lens. Git makes the changed-file
set cheap (`diff --name-status`), so only dirty boxes ever ghost, and the loupe bounds it spatially.

- **Live mode = ambient** (subtle, quiet, no red/green screaming).
- **Review / time-travel mode = focused** — the loupe + full green/red.

### 5.5 Time control surface
- A **commit timeline scrubber** (video-scrubber feel) along the bottom — drag into the past, the stage
  morphs.
- **"Live" = the right edge** of the current branch; the very tip is the **working tree** (uncommitted —
  where an agent's live edits land; distinguish it from committed history).
- **Branches as parallel translucent layers** — overlay an *unmerged branch's* proposed state as a ghost
  on top of main. That's **previewing an agent's branch / a PR spatially before you merge** — review by
  walking the diagram instead of reading a diff.

### 5.6 Staging — two products are hiding here; keep them decoupled
- **(A) The ghost overlay for live changes** — small, high-value, **no git required.** Makes
  live-overwrite safe and delivers the "watch it change" magic. **Build first.**
- **(B) Full git time-travel** (scrubber, branch layers, commit diffing) — very cool, clearly
  differentiated, but a real epic and **git-gated** (most Obsidian vaults aren't repos).

They share the ghost grammar (A is the foundation of B). The base experience must **never depend on git.**

### 5.7 Pressure-tests to hold
- **Noise:** default to subtle (a dot/tint); reserve full diff for the loupe or an explicit toggle.
- **"Accept the ghost" while editing = a real merge:** v1 keeps it to *take theirs / keep mine* (no 3-way
  UI).
- **Self-write loop discipline** (see §4.3).

---

## 6. Concurrency — when a human and an agent touch the same card

### 6.1 The asymmetry that decides everything
- **The human gives us *operations*** — we own the editor buffer, cursor, selection, every keystroke, in
  memory, before disk.
- **The agent gives us *snapshots*** — a black box doing atomic whole-file writes.

No CRDT/OT (the agent won't speak the protocol). We have a **live stream from one side, periodic
photographs from the other.** Everything follows from that.

### 6.2 The principle: merge *around* the human, never *into* them — at block granularity
Markdown is block-structured (paragraphs, headings, lists, the managed-links block). Use it:
- **Blocks the human hasn't touched → flow in live, ambient.** You write the intro while the agent
  rewrites the conclusion in front of you. *(Decision: let it flow live.)* This is the 90% case — human
  and agent are almost always in different parts of a file.
- **The block under your cursor → soft-locked.** *(Decision: soft lock.)* Presence shows here; the other
  party's writes to *this* block defer.
- **Same block, both diverged → one localized conflict ghost.**

Example that falls out free: the agent adds a `[[link]]` (managed block, app-owned) while you edit prose
(different block) — *can never collide.* The link just appears.

### 6.3 The soft-lock is **block-scoped and symmetric**
- It locks the **block under the cursor**, not the whole card — which is exactly why "flow live" and "soft
  lock" aren't in tension. Your block is calm and protected; everything else flows.
- **Symmetric:** if the agent is mid-edit on a block and *you* open it, you see its presence and *its*
  block is the one that defers. Whoever's in a block owns it.

### 6.4 The stale-base subtlety (do it right)
While you type unsaved changes, disk still holds the **old** text; the agent built its write on that old
base, never seeing your edits. That's a 3-way merge: **base** (last-saved disk), **mine** (buffer),
**theirs** (agent write) — merge per block; only true base-divergent overlaps conflict. v1 may approximate
with plain **block-ownership** (keep mine for touched blocks, take theirs for the rest).

### 6.5 Presence — make the agent a collaborator, not a poltergeist
- A halo / colored cursor: **"Agent is editing this file."**
- A fading highlight on the block it last wrote.
- Cheap to build, huge for the feel — turns "conflict" into "collaboration."

### 6.6 The save path is symmetric
Your debounce-save checks "did disk move since I loaded?" If yes, *that* save is itself a merge moment —
you don't get to blind-clobber the agent either. Any divergence, any direction → the same block-reconcile.

### 6.7 The rule (and how it honors "opt-in ghosts")
> **Ambient and quiet by default. Ghosts on demand. A true conflict forces one localized ghost regardless**
> — because a genuine collision is a decision only you can make.

---

## 7. Phased rollout

**Phase 1 — Notes linking + live read *(the spine; next sprint)***
- Draw an edge between two `.md` notes → write a `[[link]]` into the managed `<!-- canvas-links -->` block;
  delete edge → remove it; undo reverses both.
- Read existing `[[links]]` → auto-draw edges (Obsidian/agent links show up).
- File-watching makes it bidirectional + updates card content live (reload banner as the safe default).
- *This alone delivers "automatic Obsidian-like linking" + "live edits," no git required.*

**Phase 2 — Typed / labeled connections** — relationship types on edges (managed block / Dataview field).

**Phase 3 — Code references** — derived from imports/symbols (read-only) + manual comment-annotations.

**Phase 4 — Folder notes** — folder connections via materialized index files; folders gain content.

**Parallel track — the overlay / time machine**
- **3a — Ghost overlay** (safe live-overwrite + live block-flow + presence + soft-lock). Builds on Phase 1
  + live updates; no git.
- **3b — Git time-travel** (loupe review mode, commit scrubber, branch-as-layer). Later, git-gated.

---

## 8. The whole thing, in one breath

A spatial, plain-markdown graph you **edit from either side**, **watch breathe in real time**, where you
and an agent **co-edit safely** (flow live, soft-lock your block, ghosts only on real conflict), and —
when it's a repo — **scrub through its history and preview a branch before you commit.** Alive, but sober.

---

## 9. Open questions parked for later
- Managed block vs. frontmatter-mirror: ship the block; decide on the frontmatter mirror once we see agent
  round-tripping in practice.
- Exact comment-annotation syntax for code links (`// @link` vs `// @see`) — pick during Phase 3.
- Folder-note index filename convention (`Folder/Folder.md` vs `index.md`) — pick during Phase 4.
- "Accept ghost" merge: when does *take theirs / keep mine* graduate to a real 3-way UI? (Driven by how
  often true same-block overlap actually happens.)
- Is simultaneous same-file co-editing a real workflow or a demo flex? If users naturally take turns,
  block-flow is polish and deferral would've been fine — watch real usage.
