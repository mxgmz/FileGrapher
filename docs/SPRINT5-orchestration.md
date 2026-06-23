# Sprint 5 — Multi-Agent Orchestration Plan

> Planned 2026-06-23. **Plan only — no agents spawned, no code yet.** Execution model mirrors the S20
> recipe (HANDOFF) with one big difference called out below. Tickets + locked decisions live in
> `BACKLOG.md` → "Sprint 5" and `DESIGN-interaction-polish.md`.

## Roles
- **Planner + Reviewer = me (this session = plan; next session = review/merge train).** I do Phase 0
  (baseline), write the briefs, and run the serial review + merge train.
- **Executors = sub-agents**, one per *lane* (not per ticket), each in its own background git worktree.
- **Deliverable = one PR per lane.** Agents do **not** merge and do **not** drive the UI. PRs sit open;
  **we review them together in a new session.**

## The reality check (why not 8 parallel agents)
S20's 4 tickets were nearly file-disjoint, so parallel was free. **Sprint 5 is not:** almost every ticket
edits `Canvas.swift` (`NodeView`/`dragGesture`/`folderBox`/handles) and several edit `Model.swift`
(`endDrag`/`setExpanded`/`effectiveFrame`). Parallelism here is **modest and bounded by coupling**, and —
per the S20 lesson — **review/merge is serial regardless**. So we partition by **conflict-domain lane**
(the S20 rule: "partition by shared-file region, not one per ticket"), fold each ticket's dependencies
*inside* its lane, and accept that the merge train resolves a few known hotspots.

---

## Lanes (4 parallel authoring lanes + 1 deferred polish lane)

Each lane = one agent, one branch, one PR. All four authoring lanes **fork from the same Phase-0
baseline** and run in parallel. **Lane P is deferred** — it needs the integrated result, so it's spawned
*after* the merge train (or done by me as a final sweep).

### Lane F — Folders (branch `s5-folders`) — **the long pole / keystone**
- **Tickets:** T2 (folder-as-frame) → T5 (collapse + empty hint) → T6 (expandable folder-note + card
  size + header-dbl-click rename), done in that order within the lane.
- **Owns:** `Canvas.swift` — `NodeView` folder path (`folderBox`, the header-vs-interior gesture split,
  collapsed-children render filter, disclosure ▸ + count badge, empty hint, folder expanded-card, ⤢ on
  folders, header double-click rename). `Model.swift` — `BoardNode.collapsed` / `cardSize`,
  `effectiveFrame` collapse short-circuit, `isExpanded`/`setExpanded` relaxed to folders + the
  `<FolderName>.md` folder-note resolver (lazy-create on first edit), `toggleCollapse`, hidden-descendant
  helper.
- **Does NOT own:** the *push-on-expand* behavior (that's Lane C's `setExpanded` hook — F only makes
  folders *able* to expand); edges; selection chrome/handles; docs.
- **Deps:** none at fork (forks baseline). Highest hit-testing risk → most careful review.

### Lane C — Collision & Pin (branch `s5-collision`) — **central new behavior**
- **Ticket:** T4 (push-on-drop + pin).
- **Owns:** `Model.swift` — `BoardNode.pinned`, the push solver (`pushSiblings`/`resolveOverlaps` beside
  `nearestFreeCenter`), `endDrag` (replace the snap call with push; keep snap as the boxed-in fallback),
  the `setExpanded` **push hook** (covers note *and* folder expansion), resize-end hook, `setPinned`.
  `Canvas.swift` — `NodeView.dragGesture` pinned early-out + lock cursor, the pin glyph, context-menu
  Pin/Unpin.
- **Does NOT own:** folder rendering/collapse/`effectiveFrame`; edges; handle sizing; docs.
- **Deps:** none at fork. Push is **on-drop** (locked). Headless-test the solver + pin-as-obstacle.

### Lane H — Chrome & feel (branch `s5-chrome`)
- **Tickets:** T1 (hover-outline + per-region `NSCursor`) + T3 (handle size-clamp + hide chrome below
  ~0.5× zoom). Combined because both own the selection-chrome region.
- **Owns:** `Canvas.swift` — `handles`, `HandleButton`, `ResizeHandle` (sizing/zoom-hide/cursors),
  `NodeView` hover-outline overlay + body cursor, `cardHeader` cursor.
- **Does NOT own:** the folder gesture *structure* (Lane F owns it — H only adds hover/cursor); drag/push
  (Lane C); edges; docs.
- **Deps:** none at fork.

### Lane E — Connectors (branch `s5-connectors`) — **cleanest / most independent**
- **Ticket:** T7 (draggable endpoints + re-route with link rewrite, labels, hover hit-zone).
- **Owns:** `Canvas.swift` — `EdgeLine` only. `Model.swift` — `BoardEdge.label`, edge re-route mutation
  (rewrites `[[links]]` via the existing `writeLink`/`removeLink` on old & new source), label mutation.
- **Does NOT own:** nodes, folders, chrome, docs. Near-zero overlap with the other lanes.
- **Deps:** none.

### Lane P — Polish (branch `s5-polish`) — **DEFERRED, runs last**
- **Ticket:** T8 (unify radii/strokes/shadows across note/folder/card/ghost; empty-canvas hint; confirm
  chrome-hide threshold).
- **Why deferred:** it's a cosmetic sweep over the *integrated* UI — it must see F+C+H+E merged or it
  fights them. **Spawn only after the merge train**, forking from the post-merge `main` (or I do it inline
  during integration).

---

## Phase 0 — Baseline (me, before spawning) — non-negotiable
1. `main` is clean, builds (`./build-app.sh debug`), launches at ~0% CPU.
2. Everything committed + pushed — **a worktree forks the last commit, not the dirty tree** (the S20
   rule that makes branches buildable).
3. Note the baseline commit hash in the spawn briefs so each PR's diff is legible.

## Shared brief (prepended to every lane agent)
> Read first: `CLAUDE.md`, `docs/HANDOFF.md`, `docs/BACKLOG.md` (your Sprint-5 ticket rows),
> `docs/DESIGN-interaction-polish.md` (the locked decisions — esp. §1, §2, §7, §8).
>
> **Guardrails (DESIGN §7 — do not violate):** every geometry mutation goes through the undo engine
> (`transaction` / `beginInteraction`→`endInteraction`/`endDrag`); reuse `clampCoord`/`clampSize` on
> every computed coord/size; new `BoardNode`/`BoardEdge` fields are `Codable`-optional; render in screen
> space (× zoom), never `.scaleEffect` a node; `effectiveFrame` is hot — collapse short-circuits it, the
> push solver caps its cascade; never enforce collision on load; collapsed nodes stay in `board.json`
> (excluded only from render/hit-test/marquee).
>
> **Constraints:** stay inside your lane's declared file footprint; **do not edit any doc**
> (`docs/**`, `CLAUDE.md`) — the orchestrator reconciles HANDOFF/BACKLOG; **do not drive/screenshot the
> UI** — visual verification is the review step; keep the diff small and reviewable.
>
> **Definition of Done:** `./build-app.sh debug` clean (no warnings); app launches and idles ~0% CPU;
> any pure-geometry logic has a headless assert-harness test (the `nearestFreeCenter`/`ManagedLinks`
> precedent); open a **PR** whose body states what you built, what you deliberately deferred, the
> headless test results, and a **"Needs visual verify"** checklist for the reviewer. Do **not** merge.

---

## Conflict-hotspot map (for the merge train — where the lanes meet)
Forking all four from baseline means these overlaps resolve at merge, not at author time:

| Location | Lanes that touch it | Reconcile |
|---|---|---|
| `Canvas.swift` `NodeView.body` / `dragGesture` | F (folder header-only drag) · C (pinned early-out + lock cursor) · H (hover overlay + body cursor) | Merge **F → C → H**; F sets the gesture structure, C inserts the pinned guard, H layers hover/cursor on top. Small, localized. |
| `Model.swift` `setExpanded` | C (push-on-expand hook) · F (relax to folders, `cardSize`) | Merge **C → F**; keep C's push call, apply F's folder/`cardSize` logic around it. |
| `Canvas.swift` `folderBox` | F only (C/H must not touch it) | Clean if footprints held. |
| `Model.swift` `effectiveFrame` / `endDrag` | F (`effectiveFrame` collapse) · C (`endDrag` push) — *different functions* | Independent; no conflict expected. |
| `BoardNode` field block | F (`collapsed`,`cardSize`) · C (`pinned`) | Trivial additive merge. |

## Phase 2 — Review + merge train (next session, me + Max, **serial**)
1. **Review order = merge order:** **F → C → H → E**, then spawn/merge **P** last.
2. Per PR: inline `/code-review` over the diff (small diffs → review inline, don't fan out cold agents —
   S20 lesson); fix findings; `git merge-tree` against the advancing `main` to surface the hotspots
   above; resolve; squash-merge.
3. After each merge: `./build-app.sh debug` + launch (0% CPU) + a **visual pass** (the env can now drive
   the UI via the S19 recipe — hide "Codex", CGEvent helper, one-Bash-command popovers, 2× Retina).
4. After the train: spawn **Lane P** from the integrated `main` (or do T8 inline), review, merge.
5. **Orchestrator reconciles docs** (HANDOFF entry + tick BACKLOG T1–T8) — agents never touched them, so
   no doc conflicts (the single biggest S20 conflict-class, eliminated by the no-docs rule).

## Risks & mitigations (sprint-specific)
- **Canvas.swift is a shared spine.** → Strict per-lane footprints + the hotspot map + serial merge in
  F→C→H→E order. If overlap feels too heavy in practice, fall back to **staged spawn** (merge F first,
  then spawn C/H/E from post-F `main`) — fewer conflicts, less parallelism.
- **Lane F is large + keystone.** → It's the long pole; the other three finish sooner and wait in PR.
  Review F most carefully (highest hit-testing risk).
- **Push ↔ folder auto-grow recursion / oscillation (C).** → Cap the cascade; resolve child-level then
  folder-level; accept residual. Headless-test it.
- **Folder-note files created spuriously (F/T6).** → Lazy-create `<FolderName>.md` only on first edit.
- **Re-route breaking `[[links]]` (E/T7).** → Re-route must remove the old + write the new link via the
  existing managed-block machinery; headless-test the round-trip.
- **An agent strays out of its footprint** → caught at review; footprints are declared in each brief.

## Go / no-go before spawning
- [ ] Phase 0 baseline green (clean, builds, launches, pushed).
- [ ] Briefs finalized for F, C, H, E (P deferred).
- [ ] Max confirms the lane partition + that PRs (not merges) are the deliverable.
- [ ] Confirm: spawn all 4 from baseline now (one review batch next session) **vs** staged spawn.
