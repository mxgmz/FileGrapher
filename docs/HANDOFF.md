# Session Handoff — Graphing App

Newest first. **At each session's end, add an entry**: what changed, current state, next up,
open questions. At a session's start, read the top entry to pick up where we left off.

---

## ▶ NEXT SESSION — START HERE · S21 planned **Sprint 5 — Interaction Polish** (design + sprint, NO code yet)

S21 was a **planning session** (Max: brainstorm element interactions → polished product, then "just the
sprint plan for now"). Deliverables, all docs:
- **New `docs/DESIGN-interaction-polish.md`** — the design note. **🔒 Locked: (1) Folder = frame**
  (header + border live, interior = marquee/drop, not a giant click target); **(2) nothing overlaps — a
  drop *pushes* siblings, a *pinned* box is an immovable anchor**; (3) folders are both collapsible (hide
  children) and expandable (folder-note card). Plus cross-cutting engineering rules + 4 open decisions.
- **`docs/BACKLOG.md` → "🎨 Sprint 5"** — 8 tickets T1–T8 (hover/cursors · folder-as-frame · chrome
  scaling · push+pin · folder collapse · expandable folders/card polish · connector polish · micro-polish),
  each with do/files/risks/verify/deps. Build order: T1 → **T2** → T3 → **T4** → T5 → T6 → T7 → T8.
- **`CLAUDE.md`** — folder-as-frame recorded in the locked-decisions section.

**Verified-in-code while planning (don't rebuild):** `nearestFreeCenter` soft-snap exists (T4 *replaces*
its role with push, keeps it as the boxed-in fallback); folder frame-resize-without-rescale already done
(`resizedFrame`+`contentsBounds`) so T5 is only collapse + empty hint; `dropTargetId` highlight + marquee/
⌘A/group-move all exist.

**All 4 open decisions now LOCKED (DESIGN §8):** push **on-drop** (not live); folder-note =
**`<FolderName>.md` inside** (Obsidian); folder-interior click **selects the folder**; chrome hides below
**~0.5×** zoom. No forks remain — Sprint 5 is ready to build.

**Next session:** start **T1** (hover + cursors, lowest risk) and **T2** (folder-as-frame, the keystone —
highest hit-testing risk). No code written this session.

---

## ▶ S20 — shipped **4 parallel-agent PRs** (Tier-1 UX + reload banner + undo-in-rename)

S20 ran an **orchestrated multi-agent** flow: 4 background worktree agents → 4 PRs → inline `/code-review`
→ merged in order. All four are on `main` (squash-merged, integration build clean, app launches 0% CPU). The
Sprint-4 git-time-travel work (S15–S19) was committed first (`32184fa`) so branches forked from a buildable tree.

**Landed on `main` (PRs #1–#4, github.com/mxgmz/FileGrapher):**
- **#1 ⌘Z-in-rename fix** — `FieldEditor` (App.swift) routes ⌘Z/⇧⌘Z to the focused field editor's own undo
  while editing a title/card body, board undo otherwise. No `.disabled` gate (focus isn't SwiftUI-observable;
  routed closure is no-op-safe). Resolves the long-standing known issue.
- **#2 reload banner** — an external change to an in-edit card/peek raises `diskConflicts` (reuses self-write
  suppression; off while time-traveling) → a sober "Updated on disk" banner; Reload re-reads, dismiss keeps editing.
- **#3 zoom navigation** — ⌘+/−/0 (viewport-center anchored), Zoom to Fit (⌘9 + TopBar button), click-to-reset zoom %.
- **#4 empty-canvas menu + duplicate** — right-click empty → New Note (at cursor)/Paste/Select All; ⌘D + ⌥-drag
  duplicate as real "copy" files. (Double-click-empty→new-note was already implemented.)

**⚠️ Owe Max a visual pass** (all four — verification deferred to review per the workflow; build + headless only).
Each PR body has a "Needs visual verify" checklist. Highest-value to eyeball: **#1** typing-undo vs board-undo on a
fresh board (the field-editor-undo assumption); **#4** ⌥-drag = two ⌘Z (intended) + marquee still works;
**#2** Reload vs dismiss semantics. App is built at `dist/GraphingApp.app` (currently running).

**Cleanup owed:** the 4 agent worktrees still exist under `.claude/worktrees/` and the 4 remote branches weren't
deleted on merge (`--delete-branch=false`) — prune when convenient (`git worktree remove` + `git push origin --delete <branch>`).

**Next builds (pick one):** the **loupe** (last Sprint-4 polish — render the diff under a draggable lens) · remaining
Tier-2 UX (Finder drag-in, alignment guides, arrow-key nudge, collapse-folder) · or the secondary UI-verify debt
(S12 connector→wikilink round-trip, marquee, copy/paste, Quick Look) now that the UI is drivable.

---

## 2026-06-23 — Session 20 — **orchestrated 4 parallel sub-agents → 4 reviewed PRs, merged to main**
Max asked to tackle the remaining backlog in parallel: orchestrator + sub-agents, deliverables as PRs, reviewed
and merged one by one, each on its own branch. How it ran (reusable recipe):
1. **Phase 0 — baseline.** Committed + pushed the uncommitted S15–S19 Sprint-4 work (`32184fa`) so every branch
   forked from a buildable tree (a worktree forks the last commit, **not** the dirty working tree — non-negotiable).
2. **Phase 1 — author in parallel.** 4 background worktree agents, partitioned **by conflict-domain** (not one per
   ticket): zoom · creation/menu · undo-bug · reload-banner. Each got CLAUDE.md + HANDOFF + BACKLOG, a tight brief
   with a **declared file footprint**, build-clean + headless-test requirement, **don't touch docs** (orchestrator
   reconciles → kills the worst conflict class), **don't drive the UI** (visual verify = the review step).
3. **Phase 2 — review + merge train.** Ran `/code-review` **inline** over each diff (small diffs → reviewed directly,
   skipped the skill's 40-agent fan-out). One real finding: #1's `.disabled` gate was stale (field focus isn't a
   SwiftUI-observable dependency) → could swallow ⌘Z on an empty board; fixed by dropping the gate (routed closure is
   no-op-safe). Merged **#1→#2→#3→#4** (squash), `git merge-tree`-checked each against the advancing main — **all
   clean** (the predicted #1↔#4 App.swift clash never materialized: #4's Duplicate went in the `.newItem` group, not
   `.undoRedo`). Integration `./build-app.sh debug` clean; app launches 0% CPU.

**Lesson / reusable:** parallel agents save **authoring** time, not review/merge (that stays serial — it's where
quality holds). Partition by shared-file region + forbid doc edits → near-zero merge conflict. Small diffs → review
inline; don't fan out cold agents that re-derive context you already have.

---

## 2026-06-22 — Session 19 shipped **read-side link auto-draw** + cleared git-time-travel UI debt
Two things landed S19 (entries below): (1) Sprint 4 P0–P3 git time-travel is **eyeball-verified end-to-end**
and provably VIEW-ONLY; (2) the **Sprint-3 read-side gap is closed** — `[[link]]`→auto-drawn edges now works
(unit 9/9 + live integration verified). The living-canvas link spine is now **bidirectional**.

S19 also **built + UI-verified P2 edge/link diff** (edges dim / ghost across time-travel). **Sprint 4 (git
time-travel) is now fully complete and eyeballed** — only the optional **loupe** polish remains.

**Next builds (pick one):**
- **The loupe** (Sprint-4 polish) — render the time-travel diff only under a draggable lens. Last Sprint-4 item.
- **Tier-1 UX** — empty-canvas right-click menu, zoom-to-fit, ⌘+/–/0. Everyday muscle-memory gaps.
- **Secondary UI-verify debt** (now drivable): S12 connector→wikilink round-trip, marquee, copy/paste, etc.

⚠️ **Live-vault note for the read side:** opening `Graph test` with this build runs the reconcile, which will
**auto-draw edges for any `[[links]]` in notes' `<!-- canvas-links -->` blocks** and tag them `linkBacked`.
Pre-existing **hand-drawn edges are preserved** (`linkBacked == nil` is never auto-dropped). It only reads
notes + rewrites the gitignored `board.json` (never edits note prose). Full state in **BACKLOG**.

### ✅ This env CAN drive + screenshot the UI — and the technique that makes it work
Big change from S15–S18 ("couldn't screenshot"): **`screencapture` + synthetic input work now.** The recipe,
because it's fiddly (the `scratchpad/*` helpers below live in ephemeral `/tmp` — **recreate them from these
descriptions**, they're a few lines each):
- **Driving clicks/drags:** a tiny compiled Swift **CGEvent** helper (`scratchpad/mouse.swift` → `mouse
  click|drag|move X Y`). System Events `click at {x,y}` throws **-25200** (don't use it). **NSMenu items
  (e.g. the branch picker) ignore plain clicks — use press-drag-release** (`mouse drag` from the dropdown to
  the item).
- **Focus war:** the host terminal **"Codex" shares GraphingApp's exact window rect** and keeps stealing
  z-order, so clicks/captures hit Codex. Fix: **hide Codex** (`osascript … set visible of process "Codex" to
  false`) before any click/capture (see `scratchpad/raise.sh`). ⚠️ **But hiding Codex revokes bash's
  `~/Documents` file access** (TCC is tied to the host being visible → `git`/`ls`/`cat` give "Operation not
  permitted"). So **alternate: hide Codex for UI, unhide for git/file ops.** Screenshots write to `/tmp`, so
  they're unaffected either way. (The Read/Edit/Write tools also keep working regardless.)
- **Popovers auto-dismiss** when GraphingApp loses focus between Bash calls, so **open-popover + click-target
  must be in ONE Bash command** (raise → click clock → click button). Retina is **2×**: `screen_pt = px/2`.
- Accessibility (assistive access for osascript) had to be granted once via System Settings during the run.

### Secondary UI-verification debt (still owed, now checkable with the recipe above)
Not done in S19 (focused on git time-travel). From earlier sessions, still un-eyeballed: **connector →
`[[wikilink]]` round-trip** (S12), **live file-watch refresh**, **marquee multi-select / ⌘A / shift-click**,
**⌘C/⌘X/⌘V**, **Quick Look (Space) + expand cards**. Knock these out on the fixture or a throwaway vault.

---

## 2026-06-22 — Session 19 (cont. 2) — **BUILT: P2 edge/link diff** (edges dim/ghost across time-travel)
Finished the long-deferred half of Sprint-4 P2, now that edges are link-backed. While scrubbing a commit or
previewing a branch, the edge layer reflects the **link** state at that revision:
- a current link edge whose `[[link]]` **didn't exist** at the viewed commit → **dims + dashes** (like an
  "added later" box);
- a link that **existed then** but isn't drawn now → a **faded dashed ghost connector** between the two
  surviving notes (the connector counterpart to the deleted-since `HistoryGhostBox`).

**What shipped (`Model.swift` + `Canvas.swift`, no new files):**
- **`AppModel.historyEdgeDiff()`** — parses each note's `[[links]]` from the **already-loaded**
  `historicalContent` (no extra git calls), resolves them via the shared `linkTargetResolver()`, and computes
  `@Published historyAddedEdges: Set<UUID>` (current link edges absent in history → dim) + `@Published
  historyGhostEdges: [GhostEdge]` (historical links not drawn now, both endpoints surviving → ghost). Run in
  `applyHistory`; reset on return-to-live / `closeVault`. New `func isEdgeAbsentInHistory(_:)`.
- **Refactor:** extracted `linkTargetResolver()` + `unorderedPairKey()` from `reconcileLinkEdges` so the read
  side and the history diff resolve `[[name]]`→node identically (ambiguity-safe). New `struct GhostEdge`.
- **`Canvas.swift`:** `EdgeLine` gains `absentInHistory` (dims to 0.3 + dashes the stroke/arrow); the edge
  `ForEach` passes `model.isEdgeAbsentInHistory(edge.id)`. New render-only **`GhostEdgeLine`** (faded dashed
  curve + arrowhead) drawn in `historyGhostLayer` for each `historyGhostEdges`, never hit-tested.

**Verified:** `swift build` + `./build-app.sh debug` clean. **Headless 6/6** (`historyEdgeDiff` port + real
`ManagedLinks`): added=={Apex|Delta}, ghosts=={Apex|Gamma}, present-both neither, identical-history→no-diff,
link-to-deleted-node→no-ghost, legacy-nil-edge-never-dims. The reconcile harness still **9/9** after the
helper extraction. **✅ UI-verified by eye** (after the screen unlocked) on the `/tmp/gapp-linkdiff` fixture
(Apex links Beta+Gamma @v1, Beta+Delta @live): at **Live**, Apex→Beta and Apex→Delta both **solid**, none to
Gamma. **Scrubbed to v1:** Apex→Beta stayed **solid**, **Apex→Delta dimmed + dashed** (added-later), and a
**faded dashed Apex→Gamma ghost** appeared (existed then, gone now). **Back to Live** restored both to solid
and cleared the ghost. (The initial attempt was blocked because the Mac had **locked** mid-session —
`CGSSessionScreenIsLocked=1` blanks `screencapture` and stops the app drawing a window while locked.)

---

## 2026-06-22 — Session 19 (cont.) — **BUILT: read-side `[[link]]` → auto-drawn edges** (living-canvas spine)
Closed the long-standing Sprint-3 read-side gap. The managed `<!-- canvas-links -->` block is now the
**source of truth** for note↔note edges: a `[[Target]]` in the block (written by the app, an agent, or
another machine) **auto-draws an edge**; a link removed there **drops its edge** — live, via the existing
`VaultWatcher`→`syncFromDisk`. The write side (S12) + this read side make the bridge bidirectional.

**What shipped (`Model.swift` only — no new files):**
- **`AppModel.reconcileLinkEdges()`**, called at the end of `syncFromDisk` (after node reconcile + dangling
  cleanup, before `save`). Reads each note's managed block (`ManagedLinks.targets`), resolves `[[name]]` →
  node and reconciles `board.edges`. **Ambiguity-safe** (the live vault's many `Untitled`): a name shared by
  >1 note never auto-draws a guessed edge, and an existing edge is *kept* as long as some link of that name
  is still in the source block (so a user's edge to an ambiguous target is never destroyed). Resolves
  `[[Name]]` by basename and `[[folder/Name]]` by path. ponytail: re-reads every note file each sync (fine at
  this scale; cache by mtime if it bites).
- **New `BoardEdge.linkBacked: Bool?`** — `true` = this edge IS a disk wikilink (the reconcile owns it; drop
  it when the link vanishes); `nil` = a **hand-drawn visual edge the reconcile must never delete** (protects
  every pre-existing edge on the live board). Set at creation in `connect`/`spawn` when both ends are notes;
  the reconcile upgrades a legacy edge to `linkBacked` when a matching link appears. Codable-optional →
  old boards decode unchanged.

**Verified:**
- **Headless 9/9** (ad-hoc harness, like S12's `ManagedLinks` test: real `ManagedLinks` concatenated + a
  faithful port of the reconcile loop — recreate from the cases here): add, drop, keep-legacy,
  upgrade-legacy, ambiguous-no-add, ambiguous-keep, path-qualified, visual-untouched, mutual-collapse-to-one.
- **Live integration** on a throwaway `/tmp/gapp-links` vault (Apex's block links `[[Beta]]`+`[[Gamma]]`;
  Beta/Gamma/Lonely plain): launched → `board.json` had **exactly 2 edges** `Apex→Beta`, `Apex→Gamma`
  (`linkBacked=true`), **none to Lonely**. Then **externally removed `[[Gamma]]`** → within ~0.4s the watcher
  reconciled it to **1 edge** (`Apex→Beta`). `swift build` + `./build-app.sh debug` clean.

**Next up:** P2's deferred **edge/link diff** is now unblocked (edges are link-backed, so a commit/branch diff
of links is meaningful). Or the loupe / Tier-1 UX. See BACKLOG.

---

## 2026-06-22 — Session 19 — **UI VERIFICATION of Sprint 4 git time-travel (P0–P3) — all PASS, by eye**
First session that can actually **drive + screenshot** the app. Cleared the entire owed-UI-verify debt for
the git time-travel feature, on the **throwaway fixture** + a fresh `/tmp` vault (never the live `Graph
test`). Every stage confirmed visually **and** cross-checked on disk with `git`.

**Verified (all ✅):**
- **P0 enable** (fresh non-repo `/tmp/gapp-p0`): clock popover showed the **opt-in pane** ("Track this
  vault's history" + "files are never modified" copy + **Enable Version History**). Clicking it produced on
  disk: `.git`, `.gitignore` = `.graphingapp/`, one commit `edd066e "Enable Version History — baseline
  snapshot"` (author **GraphingApp**), tracked = `.gitignore`/`Note.md`/`Second.md` only (**`.graphingapp/`
  ignored**, `check-ignore` confirms `board.json`), working tree clean.
- **P0 snapshot** (same vault): external edit to `Note.md` → panel live-updated to "**1 uncommitted change**"
  + Snapshot enabled → click → new commit `a181e75 "Snapshot 2026-06-22 19:34"`, tree back to clean. (Also
  triggered the fixture's Snapshot earlier — commit `dfd8a82`, same behaviour.)
- **P1 scrub** (fixture): dragging the bottom track to **Baseline** reverted card content live — **Welcome**
  → baseline text, header swapped the edit-pencil for an **orange read-only clock**; **Notes** (added later)
  showed the **"Not in this version"** placeholder. **Back to Live** restored everything. **Boxes never
  moved.**
- **P2 structure** (fixture @ Baseline): **Notes** box **dimmed + dashed** (added-later); deleted-since
  **Scratch** appeared as a faded **dashed ghost box**. Placement: Scratch is a vault-root file (no surviving
  parent folder) so it tiled near viewport center — readable and clearly labelled; looked fine, not off.
- **P3 branch** (fixture): **Preview branch → experiment** → **Spec** card became "**v2 spec on the
  experiment branch**"; **Ideas** (deleted on the branch) **dimmed** to "Not in this version"; **Experiment**
  (only-on-branch) ghosted in; purple **"Previewing branch 'experiment' · only-on-branch files show as
  ghosts"** banner replaced the track, with **Exit**. Exit returned to live (Spec→v1, ghost gone).
- **VIEW-ONLY proof** (fixture after all of the above): still on branch **`main`**, HEAD `dfd8a82`, working
  tree **clean**, **reflog shows no session checkouts** (only the fixture's original setup ones). The sole
  session write was the intentional Snapshot. Scrubbing + branch-preview wrote nothing, checked out nothing.

**How it was driven (so the next session doesn't re-derive it):** compiled `scratchpad/mouse.swift` (CGEvent
click/drag/move — System Events `click at` throws -25200); **NSMenu branch picker needs press-drag-release**,
not a click; **hide the host "Codex" process** (it shares GraphingApp's rect & steals z-order) before any
click/capture, but **unhide it for `git`/file ops** (hiding revokes bash's `~/Documents` TCC access);
**popover + button click must be one Bash command** (popover dismisses on focus loss); Retina **2×**. All
captured in the START-HERE block above.

**Cleanup:** restored `defaults … vaultPath` → `Graph test`; removed `/tmp/gapp-p0`. **Fixture left intact**
at `/Users/maxgomez/Documents/gapp-git-fixture` (disposable; now carries the one app-made `dfd8a82` Snapshot
commit on `main`) in case Max wants to re-eyeball. Build was already clean from S18 (no code changed this
session — verification only).

**Next up:** read-side `[[link]]`→edge auto-draw (unblocks P2 edge/link diff); or knock out the secondary UI
debt (S12 connector→wikilink, live file-watch, marquee, copy/paste, Quick Look) now that the UI is drivable.

---

## 2026-06-22 — Session 18 — Sprint 4 · 3b **P3 built**: branch-as-layer (preview a branch as a ghost overlay)
Continued from P2. Preview an unmerged branch's state spatially. **Almost entirely reuse** — a branch ref is
a git revision, so P1's content time-travel + P2's ghost grammar already produce the diff. Still VIEW-ONLY.

**What shipped:**
- **`AppModel` unified "viewed revision."** Refactored `viewCommit` → private `setViewedRevision(_:branch:)`;
  `viewCommit(hash)` (scrubber, branch nil) and **`previewBranch(name)`** (P3) both delegate to it. A branch
  name flows straight through `git show <ref>:<path>` + `filesAtCommit(<ref>)`, so content + added-later
  dimming + deleted-since ghosts all work against the branch tip vs the live board. New `@Published
  previewedBranch` (label/axis), `branches`, `currentBranch` (loaded via the extended `GitState`/
  `loadGitState`). Reset in `closeVault`.
- **UI (`VersionHistory.swift`).** Panel gains a **branch picker** (shown when `branches.count > 1`): a menu
  listing branches with a checkmark on the active one; the current-branch entry exits preview. The
  `CommitScrubber` now shows a **purple branch-preview banner** ("Previewing branch 'X' · only-on-branch
  files show as ghosts" + **Exit**) in place of the commit track while `previewedBranch != nil`.

**Verified:**
- **Headless branch-diff, 6/6 PASS** on a throwaway repo: `main` {A,B} vs a `feature` branch that edits A,
  adds C, deletes B. Confirmed `show("A.md", at:"feature")` = edited; `show("B.md", at:"feature")` = nil (B
  dims as "not on feature"); `filesAtCommit("feature")` boxable∖live = **{C.md}** (the only-on-branch ghost),
  content readable. Exactly the inputs `previewBranch` feeds the P1/P2 render path.
- **Build clean** (no warnings). **App launches, 0% CPU at rest.** **Live `Graph test` unaffected** (not a
  repo → panel/scrubber/picker all hidden).

> ⚠️ **OWE MAX A UI VERIFY** (needs a multi-branch repo-vault). On a throwaway repo with a second branch:
> open the clock popover → **Preview branch → pick the other branch** → cards show that branch's content,
> files only on it appear as ghosts, files not on it dim; the bottom shows the purple banner; **Exit** /
> picking the current branch returns to live. Nothing on disk changes; no branch is checked out.

**Sprint 4 status:** P0 ✅ P1 ✅ P2 ✅(box half; edge/link diff deferred) P3 ✅. The git time-travel
prototype arc is **complete**. Remaining refinement in the spec: **the loupe** (render the diff only under a
draggable lens — focus + perf).

**Next up — options:** (a) **the loupe** (finish Sprint 4's polish); (b) close the **Sprint-3 read-side gap**
(`[[link]]`→edge auto-draw) which also unblocks P2's deferred **edge/link diff**; (c) back to Tier-1 UX
(empty-canvas right-click, zoom-to-fit, ⌘+/-/0). Recommend (b) — it's the core living-canvas spine and has
the widest downstream payoff.
Continued from P1. The "boxes fade in/out for files added/removed vs now" half. Still **VIEW-ONLY** —
ghosts are pure render; no disk writes, box positions unchanged.

**What shipped:**
- **`GitService.filesAtCommit(_:)`** — `git ls-tree -r --name-only <commit>` (with `core.quotePath=false`),
  the set of files tracked at a commit.
- **`AppModel` structure diff** — `viewCommit` now also loads `filesAtCommit` and computes
  `@Published historyGhosts: [HistoryGhost]` = files boxable-and-tracked at the commit but **absent from the
  live board** (deleted-since). `HistoryGhost` is a transient render-only type (not a `BoardNode`).
  `deletedSinceGhosts` + `ghostCenter` position each best-effort: stacked **just below a surviving parent
  folder**, else tiled near the viewport center (no stored layout exists for a deleted file). Reset in
  `closeVault` / on return to live.
- **Rendering (`Canvas.swift`)** — **added-later** boxes (exist now, absent at the commit, via
  `isAbsentInHistory`) render **dimmed (0.3) + dashed outline**. **Deleted-since** files render as
  `HistoryGhostBox` (faded, dashed, `clock.badge.xmark` + name) in a new `historyGhostLayer` overlay,
  `allowsHitTesting(false)` so it never eats clicks. Both fade with `.opacity` transition as you scrub.

**Verified:**
- **Headless structure-diff logic** on a throwaway repo (v1: Old+Gone → v2: edit Old, add New, delete Gone):
  `filesAtCommit` correct; New is added-later (absent at v1); the deleted-since set (after the boxable
  filter, which correctly drops the baseline-committed `.gitignore`) = **{Gone.md}**, content readable at
  v1. (GitService `show`/`commits`/`diff`/`filesAtCommit` all proven.)
- **Build clean** (no warnings). **App launches, 0% CPU at rest.** **Live `Graph test` unaffected** (not a
  repo → no scrubber, no ghosts).

> ⚠️ **OWE MAX A UI VERIFY** (positions of deleted ghosts are heuristic — eyeball needed). On a throwaway
> repo with history: scrub back → notes created later **dim + dash**; a note you deleted reappears as a
> faded dashed ghost beneath its old folder; **Back to Live** clears both. Tell me if the ghost placement
> looks off — it's the deliberately-approximate part (no stored layout for deleted files).

**Deferred from P2 (noted, not done):** **edge/link diff** ("edges draw/dissolve for link changes"). It
depends on the still-unbuilt **read-side `[[link]]`→edge auto-draw** (Sprint 3) — today's `board.edges` are
user-drawn, so few are link-backed and a diff would be mostly inert. Do the read-side first, then revisit.

**Next up — Sprint 4 · P3 (Branch-as-layer):** overlay an unmerged branch's state as a translucent ghost
(`GitService.branches()` exists). Or close the Sprint-3 gap first (read-side link auto-draw), which also
unlocks the deferred edge diff above. Later: the loupe (diff under a draggable lens).

---

## 2026-06-22 — Session 16 — Sprint 4 · 3b **P1 built**: commit scrubber + content time-travel
Continued straight from P0. **VIEW-ONLY honored** — scrubbing only re-routes card/peek *content*; box
positions never move and disk is never written while viewing history.

**What shipped:**
- **`AppModel` time-travel** (`// MARK: Time-travel`): `@Published viewedCommit` (nil == live) +
  `isTimeTraveling`; `viewCommit(hash)` loads every note's content at that commit **off-main** (`git show`
  per relPath, `updateValue` so an absent file stores a real `nil` rather than dropping the key) into a
  `historicalContent` cache, then bumps `diskRevision` so open cards/peeks re-read. **`fileText` is now
  commit-aware** (returns cached historical text while traveling, live disk text otherwise);
  `isAbsentInHistory` reports a file that didn't exist at the viewed commit; **`saveFileContent` no-ops
  while traveling** (history is read-only). Reset in `closeVault`.
- **`CommitScrubber`** (in `VersionHistory.swift`, mounted as a bottom overlay on `CanvasView`) — a track
  with one stop per commit + a rightmost **Live** stop; tap/drag snaps to the nearest stop and calls
  `viewCommit`. Label shows the viewed commit (short-hash · subject · relative date) or "Live", a busy
  spinner, and a **Back to Live** button. Shown only when version history is enabled and there's ≥1 commit
  (so it's invisible on the non-repo live vault). Stop math: stop 0 = oldest … stop `count` = live.
- **Read-only affordances** in the expanded card (`Canvas.swift`) and peek (`FileContent.swift`): the edit
  pencil is replaced by an orange clock while traveling; an absent file renders a **"Not in this version"**
  placeholder (`clock.badge.xmark`); an `.onChange(of: viewedCommit)` drops any in-progress edit and reloads
  (the `diskRevision` reload is otherwise skipped while editing).

**Verified:**
- **Headless P1 routing, 7/7 PASS** on a throwaway repo: built a 2-commit history where v2 adds `New.md` +
  edits `Old.md`, then reproduced exactly `viewCommit`'s cache build + `fileText`/`isAbsentInHistory`
  routing: at HEAD both notes show v2 content; at v1 `Old.md` shows the **old** text and `New.md` is
  **ABSENT** (→ "Not in this version", routes to empty text). (GitService's own `show`/`commits`/`diff`
  were 22/22 in S15.)
- **Build clean** (`./build-app.sh debug`, no warnings). **App launches, stays alive** ~0–2.5% CPU.
  **Live `Graph test` vault unaffected** — not a repo, so the scrubber stays hidden and nothing changed.

> ⚠️ **OWE MAX A UI VERIFY** (can't drive the scrubber/cards headlessly). On a **throwaway** repo-vault with
> a few commits: drag the bottom strip left → expanded cards show that commit's content, the header shows a
> read-only clock, a note added after that commit reads "Not in this version"; **Back to Live** restores.
> Confirm boxes don't move while scrubbing and that no file is modified on disk.

**Next up — Sprint 4 · P2 (Structure + link diff):** boxes fade in/out for files added/removed vs now;
edges draw/dissolve for link changes (the 3a ghost grammar). `GitService.diffNameStatus(from:to:)` already
exists for it. Still VIEW-ONLY. (Then P3 branch-as-layer; later the loupe.)

---

## 2026-06-22 — Session 15 — Sprint 4 · 3b **P0 built**: git plumbing + opt-in + read-only commit list
Took 3b straight off the design (entry below) and built **P0**. **VIEW-ONLY honored** — the only disk
writes are the opt-in `git init` and explicit Snapshot commits; nothing checks out/restores/overwrites
the working tree.

**What shipped:**
- **New `Sources/GraphingApp/GitService.swift`** — pure Foundation, zero-dep shell-out to `/usr/bin/git`
  (`-C <vault>`), the `ManagedLinks`/`VaultWatcher` precedent. Read-only: `isRepo` (symlink-safe
  `show-toplevel`==root, so a vault merely *nested* in another repo reads false), `currentBranch`,
  `branches`, `commits` (unit-separator pretty-format → `Commit` structs, newest-first), `uncommittedChangeCount`
  (`status --porcelain`), `show(path,at:)` (`git show <c>:<path>`), `diffNameStatus(from:to:)`. Two opt-in
  writes only: `enableVersionHistory` (`init` + append `.graphingapp/` to `.gitignore` + `add -A` + baseline
  commit) and `snapshot` (`add -A` + commit, false when nothing staged). Robust `Process` runner drains
  stderr on a side queue (no deadlock); commits fall back to a local `user.name/email` if the repo has no
  identity; env sets `GIT_TERMINAL_PROMPT=0`.
- **Wired into `AppModel`** (`// MARK: Version history`): `@Published versionHistoryEnabled / commits /
  uncommittedCount / gitBusy`; `gitService` accessor; `refreshVersionHistory` / `enableVersionHistory` /
  `snapshot` run git **off the main thread** (`Task.detached` → `nonisolated loadGitState` → main-actor
  `apply`). `refreshVersionHistory()` on `openVault` (read-only — does NOT enable); state reset in
  `closeVault`. `handleDiskChange` now also filters `.git` paths (the watcher shouldn't churn on commit
  plumbing).
- **New `Sources/GraphingApp/VersionHistory.swift` + TopBar clock button** — popover: opt-in pane
  ("Enable Version History", explains files are never modified) when not a repo, else a **Snapshot** button
  (disabled when clean) + a scrollable read-only commit list (subject · short-hash · author · relative date).
  Clock tints when enabled.

**Verified:**
- **GitService headless, 22/22 PASS** on a throwaway temp repo (NOT the live vault — S14 lesson): not-a-repo
  → enable → `.gitignore` has `.graphingapp/` → 1 baseline commit → sidecar write stays *clean* (ignored) →
  snapshot-when-clean returns false → edit → 1 change → snapshot → 2 commits newest-first → `show` returns
  original vs edited content → `diff --name-status` reports the changed file only.
- **Build clean** (`./build-app.sh debug`, no warnings — cleared a Swift-6 `self`-capture warning by hopping
  through the main-actor `apply` instead of a nested `MainActor.run`).
- **App launches, stays alive** ~0–3% CPU (no spin). **Live `Graph test` vault confirmed untouched** after
  launch — no `.git`, no `.gitignore` (open only *reads* `isRepo`).

> ⚠️ **OWE MAX A UI/DISK VERIFY** (can't drive the popover headlessly). On a **throwaway** vault (do NOT
> enable on the live `Graph test` unless Max wants its history tracked): click the **clock** in the top bar →
> "Enable Version History" → a `.git` + `.gitignore` (listing `.graphingapp/`) appear and one baseline commit
> shows. Edit a note → the panel shows "1 uncommitted change" → **Snapshot** → a new commit appears. Confirm
> `board.json` is gitignored (positions don't time-travel).

**Next up — Sprint 4 · P1 (Scrubber + content time-travel):** a bottom commit strip (right edge = working
"live", then HEAD back); dragging it sets the viewed commit; expanded cards render `git show <commit>:<path>`;
positions stay fixed. GitService already exposes `show`/`commits`/`diffNameStatus` for it. Keep VIEW-ONLY.

---

## 2026-06-22 — Direction set — next: Living Canvas 3b · Git time-travel (prototype) — DESIGN ONLY, no code yet
Max picked **3b (git branch visualization / history)** as the next build, straight at it. Full plan +
locked decisions in **BACKLOG "Sprint 4 · 3b"**. The essentials for whoever picks this up:
- **VIEW-ONLY is non-negotiable** — render past state via `git show`; **never** `git checkout` or write
  the user's files. The canvas is a viewer over history; disk stays at working state.
- Locked: **opt-in `git init`** ("Enable Version History" button — vault isn't a repo yet); **manual
  Snapshot** commits (no auto-commit); **board.json gitignored** (positions don't time-travel); **git CLI**
  shell-out (zero-dep); **build/test on a throwaway repo-vault, not live `Graph test`**.
- Start at **P0** (git plumbing + opt-in + read-only commit list) before any canvas morphing.
- Status check that prompted this: git time-travel was **0% started** and the vault **is not a repo** —
  this is the furthest-out, git-gated item; P0 de-risks it.

---

## 2026-06-22 — Session 14 — folder geometry fixes: move-aware sync · heal stranded children · spawn-near-parent
**Context:** after live-watching shipped, a folder rename "broke it" — sidebar didn't update + a **huge,
unclickable Folder 7**. Probe (`/tmp/fsprobe.swift`) found a directory rename emits **only the two dir
paths** (`Renamed|isDir`), no descendants — so an *in-app* rename is fully self-write-suppressed (watcher
doesn't even sync). The real culprits were latent: a stranded child (S10 remnant) ballooning a folder via
auto-grow, and `syncFromDisk`'s lossy path-set diff collapsing an *external* rename's subtree to a corner.

**What shipped (`Model.swift`):**
- **Move-aware `syncFromDisk` (Fix 1).** New `BoardNode.fileId` (disk inode, Codable-optional, backfilled
  each sync). Before drop/add, a box whose path vanished but whose inode now lives at a new path is
  **repointed (position + UUID kept)** instead of dropped+re-added. Kills the external-folder-rename
  subtree-collapse. `static inode(of:)` helper. *Edge case:* inode reuse after delete could mis-map (rare;
  guarded by "don't claim a path another node owns").
- **Spawn-near-parent (Fix 3).** New boxes from sync land **next to their parent folder's children** (or
  the folder box, else viewport center), never the old fixed (9600,9800) corner — so even if move-detection
  misses, a re-add no longer strands. `spawnCenter(forNew:index:)`.
- **Heal stranded children (Fix 2).** `reinInStrandedChildren()` (run in `openVault` after sanitize):
  deepest-folders-first, for any folder whose `effectiveFrame` exceeds `maxSaneFolderSpan` (20000), pull
  children >`strandRadius` (12000) from the sibling **median** back in (rigid-body w/ their subtree) and
  reset a bloated stored frame. Fixes the unclickable folders. Helpers `moveSubtree`, `median`.

**Verified on Max's REAL board (headless):** heal ran on relaunch → Folder 6 stored **114148×98109 → 340×230**,
all folder child-spans now ≤~5700px (was ~116000), nothing >20000 → folders clickable. Mirror is **complete
+ duplicate-free**: every disk file has a box, **0 at the corner**, board ⊆ disk. Watcher still 0.31s, app
alive, no crash, **no runaway auto-move** (disk md5 stable over 4s). Build clean, no warnings.

> ⚠️ **Move-aware sync (Fix 1) NOT cleanly verified end-to-end.** While testing an external folder rename
> on the **live** vault, my test folder tangled with Max's concurrent in-app dragging (the app's `rawMove`,
> not my code — my sync never moves files). **Lesson: never run write/stress tests on the live vault while
> Max is using it.** Verify Fix 1 in an **isolated temp vault** (or with Max not interacting). Note: even
> without move-detection, spawn-near-parent already prevents the corner-collapse, so Fix 1 is a
> position/UUID-preserving *upgrade*, not the sole safety net.

> 🧹 **Vault left tangled, by Max's choice ("Leave it — I'll fix it"):** `Folder 7/RenameTest/Folder 6/…`
> (his Folder 6 nested under my test `RenameTest`) + my `note.md`. **Do not auto-clean** — Max reorganizes it.
> Board matches disk (no phantom nodes); `board.json.bak-heal-*` is the pre-heal backup.

**Next up:** isolated verify of Fix 1; decide whether to also cap `effectiveFrame` as a belt-and-suspenders;
the "name didn't update" was likely a beep-fail (rename to existing name) or undo — not a watcher revert.

---

## 📍 Session 13 (PLAN) — re-file bug + snappy resize + no-overlap hitboxes  (WS1/WS2 now built)

> Brainstormed with Max 2026-06-21. **No code written yet — this is the build plan.** Three asks, one
> underlying primitive: a box **hitbox** (= its `effectiveFrame`) + a no-overlap rule. Build in the
> order below; each step de-risks the next. Line numbers are *current-as-of-writing* — **grep the
> symbol, not the number** (`Model.swift` is actively changing).

**⚠️ Guardrails — do not break:**
- Every geometry mutation goes through the undo engine: `transaction {}` or
  `beginInteraction()`→`endInteraction()`/`endDrag()`. Never mutate `board.nodes[i]` outside it, or
  undo/redo + disk desync. (`// MARK: Undo / redo`.)
- Coords/sizes are clamped on write (`clampCoord`/`clampSize`, S10 meltdown guard). Reuse those for any
  geometry you compute — don't write raw values that could re-enter the ±1e6 meltdown zone.
- Render in screen space (× zoom); never `.scaleEffect` a node.
- **New cross-feature risk (Living Canvas):** connectors are now real `[[wikilinks]]` written into files
  (`Links.swift` / `ManagedLinks`). **Re-filing or renaming a note changes its path** → a wikilink in
  *another* file pointing at it can go stale. WS1/WS3 must not silently break links — at minimum test a
  connected pair before/after a move and leave a TODO if link-rewrite is out of scope.
- Verify each step: `./build-app.sh debug`, then Max does the visual pass (env can't screenshot).
  Live vault `/Users/maxgomez/Documents/Graph test/` (~26 nodes, 7 folders).

**Open decisions — confirm with Max before coding the affected WS (recommendation in *italics*):**
1. WS1 re-file target = box **center** (today) vs *cursor / max-overlap*.
2. WS2 "snappy" = *collision-snap to contents* vs grid-snap.
3. WS3 overlap resolution = block / push / *soft-snap on drop, siblings-only*.

---

### WS1 — Re-file bug: can't move a file from folder 6 into nested folder 7 (do FIRST — low risk, high value)

**Root cause** (read `endDrag`, Model.swift ≈772–805):
- Target = `folderNode(containing: current.center, excluding: id)` (≈796): the dragged box's **center**
  must land inside 7's grown frame, with **no highlight** of the pending target → fiddly + invisible.
- Center in 6 but not 7 → `folder.relPath == current.parentRel` → does nothing (≈799); the root-fallback
  `else if` (≈800) can't fire because a folder *did* contain it.
- Same-name target → `relocate` bails on `vault?.exists(newRel) == false` (≈786) **silently** (no beep).

**Steps:**
1. **Target by cursor, not center.** Thread the drop point from `dragGesture.onEnded` (Canvas.swift ≈910–916)
   into `endDrag`; pick the folder under the cursor (or the one the dragged box overlaps most). Keep the
   `excluding: id` self-exclude and the folder-into-own-descendant guard (≈797–798).
2. **Live drop-target highlight.** Reuse the connector precedent — `pendingConnect.hoverTarget` draws an
   outline (Canvas.swift ≈388–395) set during `connectDrag` (≈467–481). Add `@Published dropTargetId: UUID?`,
   set in `dragGesture.onChanged`, render an outline, clear onEnded.
3. **Audible block.** In `relocate`, when the name exists, `NSSound.beep()` (precedent: `rename`, grep
   `NSSound.beep`).

**Touched:** `Model.swift` (`endDrag`; `folderNode`/`smallestBox` ≈531–555; new `@Published dropTargetId`
by the viewport state ≈310). `Canvas.swift` (`dragGesture` ≈887–917; new highlight mirroring
`pendingConnector` ≈377–399).
**Risks:** border drops mis-routing — keep both guards. Don't thrash `dropTargetId` (set only on change →
no re-render jank). Link staleness (guardrails).
**Verify:** 6→7 lands in 7; drag to empty canvas → root; same-name target beeps + stays put; folder can't
drop into itself/descendant; one ⌘Z reverses move + reposition together.

---

### WS2 — Snappy (container) folder resize — stop rescaling contents

**Now:** `applyFolderResize` (Model.swift ≈1181) scales every descendant's size+position by the resize
ratio = the "resizes everything at once" Max dislikes. `ResizeHandle` (Canvas.swift ≈963–1021) snapshots
`childStart` and calls it for folders.
**Want:** resize moves only the folder frame; children stay put; inward shrink **snaps to the contents'
bounding box** (already can't draw smaller — `effectiveFrame` auto-grow).

**Steps:**
1. In the folder branch of `ResizeHandle` (≈1010–1013) call `setFrame` instead of `applyFolderResize`;
   delete the now-unused `childStart` snapshot (≈968, 982–985). Children stop moving.
2. **Clamp inward** so the dragged corner can't cross `contentsBounds + folderPadding + folderHeaderHeight`
   (constants Model.swift ≈337–341). Add a small `contentsBounds(of:)` next to `effectiveFrame` (union of
   `directChildren` effective frames) and clamp `newFrame` to enclose it.
3. (Only if Max picks grid-snap) round the dragged edge to an N-pt grid.
4. Delete `applyFolderResize` if nothing else calls it (grep first).

**Touched:** `Model.swift` (`applyFolderResize` ≈1181; maybe new `contentsBounds`). `Canvas.swift`
(`ResizeHandle` ≈963–1021).
**Risks:** an **empty** folder must still shrink to `folderMinSize` (200×150). Don't touch
drag-moves-contents (`dragGesture`/`dragGroup`) — different path. Confirm one resize = one ⌘Z after removing
`childStart`.
**Verify:** grow → kids stay, empty space added; shrink → stops at kids' edge; empty folder → min; one ⌘Z reverses.

---

### WS3 — No-overlap hitboxes (do LAST — biggest blast radius)

**Want:** "every card has a hitbox, no files on top of each other." Recommended shape (confirm decision 3):
**soft-snap on drop, siblings-only.**
- Hitbox = `effectiveFrame` (AABB); overlap = `rect.intersects`. n² is nothing at this scale.
- Scope = **siblings** (same `parentRel`). A folder *must* contain its children — only sibling-vs-sibling
  overlap is illegal.
- On drop (in `endDrag`, **after** re-file since that changes `parentRel`), overlap → nudge to nearest free
  spot (spiral search) or refuse + snap back. Live drag stays free.

**Steps:**
1. Add `overlapsSibling(_:)` + `nearestFreeCenter(for:near:)` near the lookups (Model.swift ≈520–555),
   `effectiveFrame` + same-`parentRel` filter.
2. Call at drop time inside `endDrag`'s `commit`/`transaction` so the nudge is one undo step.
3. **Do NOT enforce on load** — existing boards overlap; a global "settle" would yank Max's layout. New
   moves/resizes only.

**Touched:** `Model.swift` (new helpers; hook `endDrag`; maybe resize-end for folder-vs-sibling).
`Canvas.swift` only if adding a "can't drop here" tint.
**Risks:** highest — depends on WS1 (drop point) + WS2 (resize). Folder auto-grow makes hitboxes dynamic →
a resolved spot can re-collide; cap the search, accept "good enough." Never enforce parent↔child. Nudge
must share the drag's undo step.
**Verify:** drop onto a sibling → slides to nearest gap; can't end overlapping a sibling; folders still
contain kids; loading an already-overlapping board does NOT reshuffle; one ⌘Z reverses the whole gesture.

---

## 2026-06-21 — Session 12 — Living Canvas Phase 1: connector → real `[[wikilink]]` (write side)
**Ask:** start Sprint 3 / Living Canvas Phase 1 — make a connector a real link in the file.

**What shipped (the write side of the spine):**
- **New `Sources/GraphingApp/Links.swift` — `ManagedLinks`.** Pure, Foundation-only read/write of the
  app-owned `<!-- canvas-links -->` block: `targets(in:)` parses the wikilinks listed in the block
  (strips `[[A|alias]]` / `[[A#heading]]`); `write(_:into:)` rewrites *only* between the markers
  (deduped, order-preserved), appends a clean block with a single blank-line seam when none exists, and
  removes the block (collapsing the seam) when the list goes empty. **Never touches user prose.**
- **Wired into the model.** New `AppModel.rewriteFile(_:_:)` applies a text transform and records the
  write on the active transaction's `txnFileUndo/Redo` — so the file change rides the **existing paired
  board+disk undo engine** (one ⌘Z reverses both). New `writeLink`/`removeLink` (+ `isLinkable` =
  markdown note) called from `connect` (manual connect), `spawn` (`+`-handle sibling), and `deleteEdge`.
  Drawing A→B writes `- [[B-name]]` into A.md's block; deleting the edge removes that line. Folder/CSV/
  code edges stay visual-only (no-op). `board.edges` is **still** the drawn source of truth this session.

**Verified:** `swift build` + `./build-app.sh debug` clean; app launches & idles at **0% CPU** (no
meltdown). **Headless-tested the pure transform** — concatenated the real `Links.swift` with an assert
harness and ran via `swift`: **12/12 pass** (empty-file append, prose seam w/ & w/o trailing `\n`,
in-place update keeping surrounding prose, end + mid-file removal w/ seam collapse, dedup, no-op,
alias/heading strip, round-trip, add-then-remove). Live vault has no pre-existing `canvas-links` blocks
(clean slate).

> ⚠️ **OWE MAX A VISUAL/DISK VERIFY** (can't draw an edge headlessly here). On the live vault
> `/Users/maxgomez/Documents/Graph test/`:
> 1. Connect two **distinctly-named** notes — drag from one note's `+` handle onto another (suggest
>    **`Peek demo`** → **`HI`**, both unique basenames). Then check `Peek demo.md` on disk — it should
>    gain a `<!-- canvas-links -->` block listing `- [[HI]]`, with your existing text untouched.
> 2. Open `Peek demo` in **Obsidian** → the link should be live/clickable.
> 3. **⌘Z** → the block disappears and the edge is gone (board + disk reversed together). **⇧⌘Z** re-adds.
> 4. Delete the connector (click line → Delete) → the `[[HI]]` line is removed from the block.
> 5. Spawn a sibling note via a note's `+` handle → the source note's block gains `[[Untitled…]]`.

**Next up (read side — next increment):** in `syncFromDisk`, parse every `.md` note's wikilinks and
**reconcile into `board.edges`** (auto-draw an edge for a link present on disk; drop a link-backed edge
whose link vanished; leave folder/code visual edges alone). Resolve `[[name]]` → node by basename —
**mind the many `Untitled` collisions** in the live vault (may need path-qualified `[[folder/name]]` or
a nearest-match rule). Then live file-watching (FSEvents + self-write suppression) and the reload banner.

**Known limitations (acceptable for the write-side increment):** rename of a note doesn't yet update
incoming `[[oldname]]` links elsewhere (Obsidian-style link-update is out of scope); deleting a node
leaves dangling incoming links (as Obsidian does); basename ambiguity is a read-side problem, deferred.

---

## 2026-06-21 — Session 12 (cont.) — Live file-watching (the read side) + an FSEvents crash fix
**Ask (Max):** "live refresh now" — make open content cards/peeks re-read the moment a file changes on
disk (the staleness he hit after connecting: the source card cached its text on open and never refreshed).

**What shipped:**
- **New `Sources/GraphingApp/VaultWatcher.swift`** — a zero-dep FSEvents wrapper (CoreServices). Watches
  the vault tree, coalesces each save's burst (0.15s debounce), and reports changed **vault-relative**
  paths. ⚠️ **Must pass `kFSEventStreamCreateFlagUseCFTypes`** (+ `FileEvents` + `NoDefer`): without it
  `eventPaths` is a C `char**`, and the `NSArray` bridge messages garbage → **hard crash on the first
  event** (found & fixed mid-session; the crash `.ips` pointed straight at `VaultWatcher.swift` /
  `objc_msgSend` on the `app.graphing.vaultwatcher` queue).
- **Wired into `AppModel`** — `@Published diskRevision` bumps on any non-`.graphingapp` change; the
  expanded card (`Canvas.swift`) and peek (`FileContent.swift`) now `.onChange(of: model.diskRevision)`
  re-read from disk — **guarded by `!editing`** so an in-progress edit is never clobbered. Re-reading
  after our *own* link-write is what makes a drawn connector's `[[link]]` appear live in the source card.
- **Self-write suppression** — every `raw*` disk op calls `markSelfWrite(rel)`; `handleDiskChange` runs
  the structure reconcile (`syncFromDisk`) only for **external** changes (`isRecentSelfWrite` < 2s window)
  and **never mid-interaction** (`interactionBefore == nil`), so the app's own writes don't loop or yank a
  drag. Content re-read fires for both (it's read-only + edit-guarded).
- Watcher starts in `openVault`, stops in `closeVault`.

**Verified (headless, end-to-end):** `swift build` clean (no warnings). Proved the watcher with file
breadcrumbs + a `board.json` poll: an **external `create` reconciles in ~0.26s, `delete` in ~0.5s**, app
stays alive (0% CPU, no loop). os_log isn't queryable in this env — used a temp `/tmp` breadcrumb to
confirm `handleDiskChange` fires with the right `relevant` paths and that `.graphingapp` echoes are
filtered; **breadcrumbs since removed.** Content-refresh of an *open card* couldn't be eye-verified
headlessly (needs the UI) but the mechanism is proven sound.
> **Owe Max:** open `Peek demo`'s card, then edit it in Obsidian (or connect another edge) → the card
> should update within ~0.5s without reopening. And: external create/delete a note → box fades in/out live.

**Cross-feature note (Max editing in parallel):** Max was mid-**WS1** (re-file drop-point) in `Canvas.swift`.
His edit called `canvasLocal(...)` from `NodeView`, but it was a `private func` on another struct → red
build. Per his pick, **hoisted `canvasLocal` onto `AppModel`** (it owns `canvasFrameGlobal`) and routed all
call sites through `model.canvasLocal(...)`, removing the duplicate. Tree now builds clean with both
features. (His WS1 model-side `dropTargetId`/`dropTargetHighlight`/`endDrag(_:at:)` are in but unverified.)

**Next up:** the **read side** of links (still the gap): parse `[[wikilinks]]` on disk → auto-draw edges
in `syncFromDisk` (now that live-watching will call it automatically). Then the conflict **reload banner**
+ the stale-card edit-clobber guard (editing a card opened before an external change still saves over it).

---

## 2026-06-21 — checkpoint (end of Sessions 1–9) — MVP feature inventory & verification debt

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

**Direction set (S11) — the "Living Canvas" vision:** long brainstorm with Max produced a full spec,
[`docs/VISION-living-canvas.md`](VISION-living-canvas.md). Core thesis: *a connector is a real link in the
file* → the canvas and vault become one live graph; a spatial, real-time, agent-collaborative front-end to
plain markdown. Locked decisions: links live in a managed `<!-- canvas-links -->` block (manually drawable;
style in board.json); live file-watching makes it bidirectional; concurrency = block-scoped **soft-lock** +
non-overlapping blocks **flow live** + one localized conflict ghost; the ghost overlay is the safe face of
live-overwrite and seeds a git **time-travel loupe**; guiding aesthetic **"alive but sober."** **Phase 1 is
now the next sprint** ("Sprint 3 · Living Canvas Phase 1" in BACKLOG): connector→`[[wikilink]]` round-trip +
read-side auto-draw + live file-watching, no git required. Finish marquee/multi-select visual verify first.

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
