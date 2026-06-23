# Vision — The Agent Cartographer

> Captured from the 2026-06-23 brainstorm (Max + Claude). The product/UX spec for **agents that organize
> the canvas with taste** — the layer that sits on top of the Living Canvas. **No code here** — principles,
> the model of "taste," the intent vocabulary, and a rough phasing. `VISION-living-canvas.md` is the
> prerequisite (connectors are real links); this answers *who draws the map and how it stays readable*.

---

## 0. The thesis (the one idea underneath everything)

The Living Canvas established three axioms: a box *is* a file, a folder *is* a directory, a connector *is*
a real link. This vision adds the actor:

> **An agent can author and maintain the canvas with taste — read your vault and keep it a readable map.**

The app stops being only a place *you* arrange and becomes **a territory that organizes itself** when you
ask it to. That moves the product from "a spatial front-end to a markdown brain" to **"a self-organizing
one."**

The single technical idea that makes this buildable:

> **The agent never pushes pixels. It speaks *intent*; the app's existing geometry resolves intent into
> coordinates.**

An LLM has no eyes and no spatial sense — ask it for raw `x,y` and you get garbage. But you already built
the spatial competence (auto-grow, sibling-push, non-overlap, zoom, collapse). The agent only needs a
*vocabulary that aims it.* Everything below follows from that one separation.

---

## 1. Decisions locked this session

| Topic | Decision |
|---|---|
| Scope | **Both, one capability** — cold-start scaffolding and tidying an existing pile are the *same gesture*; only difference is whether the files exist yet |
| Interaction | **Conversational** — you talk, it edits the canvas live; you nudge, it adjusts (not one perfect shot) |
| Default layout | **Radial mind-map**, but the agent switches per content (columns for a process, grid for a catalog) |
| Hub selection | **Agent decides case-by-case** — use the folder-note, promote an obvious center, or mint a fresh index |
| Blast radius | **Whole canvas, global coherence** — free to rearrange everything so the board reads well together |
| Safety model | **Undo is the preview** — the agent acts boldly; ⌘Z is the veto. No approval UI |
| Confidence | **Visual** — sure links solid, inferred links dashed (reuse the absent-in-history dashing) |
| Stability under freedom | **Minimal-motion + gravity + learned ontology** (see §6) |

---

## 2. "Taste" is a stack of four decisions, not one skill

When a human arranges a folder and it *looks right*, they made four decisions at once. Naming them
separately is the whole trick — because the LLM is brilliant at two and useless at two.

| Layer | The decision | Who's good at it |
|---|---|---|
| **1 — Structure** | The set of notes + folders and the hierarchy ("these 40 thoughts are 4 themes") | **LLM-native** — pure meaning |
| **2 — Connections** | Which note links to which — real `[[wikilinks]]` + drawn edges. Authoring the graph | **LLM-native** — pure meaning |
| **3 — Placement** | Structure + graph → 2D that *reads*: alignment, spacing, clusters, flow, no overlap | **App's job** — LLM is bad here; emits intent, app resolves |
| **4 — Emphasis** | What's loud: which boxes are expanded cards vs title chips, what's collapsed | **Split** — LLM picks the narrative, app supplies the styling |

The leverage: **let the LLM do 1–2, hand it strong primitives for 3, let it nominate 4.** Never let it
compute coordinates.

---

## 3. The cartographer — what it actually is

A conversational collaborator that holds a model of your whole vault and keeps it a **fractal radial map**:

- **The map has altitude.** Top level is constellations — folders as hubs in their neighborhoods. Zoom
  into one and it *unfolds into its own radial* of children; zoom again, sub-hubs. Your existing
  **zoom + folder-collapse + auto-grow** already are this primitive — radial recursion + collapse = a map
  with levels. You never see 500 notes; you see the right ~7 for your altitude.
- **Hubs are chosen, not fixed.** Per node the agent decides: the folder-note, the promoted center, or a
  freshly minted index. Case by case, like a person. (Radial maps cleanly onto the folder model: a
  folder-note *is* a hub, its children *are* the spokes.)
- **Emphasis follows focus.** Hubs render as expanded cards (the loud boxes); leaves stay as title chips.
  Focus a region in conversation → the relevant files *bloom open*; pan away → they fold back. Progressive
  disclosure tied to where you're looking. *(This is Max's original "expand the right files.")*
- **Links are the territory's roads** — drawn as real `[[wikilinks]]` (Living Canvas), solid when the
  agent is sure, dashed when it's guessing.

**Two walkthroughs (the feel):**

*Cold start* — "Mind-map a plan for my Berlin trip." → a `Berlin Trip` folder appears, a folder-note hub
expands at center, five chips radiate (Flights, Stay, Food, Itinerary, Budget), links fan out. *"Made a
hub + 5 branches. Want days under Itinerary?"* → "4 days" → four sub-chips bloom off Itinerary as a
sub-hub.

*Tidy* — point at 30 loose notes, "Organize this." → it reads them, crowns `Overview` the hub, clusters
the rest into 3 themed sub-hubs, draws the links it infers from the prose, aligns radially, expands the
hub. *"Found 'Overview' as your center + 3 themes. The 6 links I guessed are dashed — check those."* →
"the API note isn't research, move it out" → done. ⌘Z anything.

---

## 4. The design laws (sibling to "alive but sober")

If a feature breaks one of these it's probably wrong:

1. **Never pushes pixels.** The agent emits intent (§5); the app owns every coordinate. The instant the
   agent reasons in `x,y`, quality collapses.
2. **Minimal-motion.** The agent must *earn* a rearrange with a reason. Absent one, boxes stay put — the
   human navigates by remembered location, and a bulldozer that "improves" the layout every time is hostile
   even when it's right. A good editor, not a redraw.
3. **Gravity, not randomness.** A new note scribbled anywhere drifts toward its kin. The global model means
   boxes land *near their neighborhood*, never wherever the cursor happened to be.
4. **Confidence is visible.** Sure things solid, guesses dashed. Taste includes saying "this is my guess."
5. **Undo is the preview.** Every agent edit runs through the existing `transaction{}` engine → ⌘Z is the
   reject button. Don't build an approval UI; you already have one. Conversational + undo lets the agent be
   bold.
6. **Learns your ontology.** When you say "fitness and health are one cluster to me," it sticks (the memory
   system is exactly for this). Global coherence becomes *your* coherence over time, not the model's.
7. **The map has altitude.** Never render 500 boxes at once. Coherence is per-altitude — constellations up
   high, a clean radial of ~7 when you zoom in.

---

## 5. The intent vocabulary (the bridge to "how")

The contract between agent and app. A small verb set the agent emits; the app resolves each into geometry
using machinery that already exists. *(Exact surface — names, transport — is for the follow-up; this is the
shape.)*

| Intent | Means | Resolves via |
|---|---|---|
| `hub(node)` | Make this the center of its cluster | expand as card, anchor the radial |
| `spoke(child, of: hub)` | Hang a node off a hub | radial placement around the hub |
| `cluster(nodes, theme)` | Group these as a neighborhood | folder + sibling-push to a clear region |
| `link(from, to, type?)` | A relationship | writes the `[[wikilink]]` / managed block (Living Canvas) |
| `expand(node)` / `collapse(node)` | Loud vs quiet | `node.expanded` / folder-collapse |
| `place(node, near: other)` | Gravity hint | nearest free slot to `other` |
| `pin(node)` | Don't move this | the existing pin (obstacle, immovable) |

The agent says *"cluster these three under that folder-note as a hub, link A→B"* — the app figures out
where the pixels go. **The agent authors meaning; the app authors layout.**

---

## 6. Whole-canvas freedom without chaos

The bold pick (rearrange *everything*) collides with the human's **spatial memory**. Three principles keep
global freedom humane — they *are* laws 2, 3, 6 above, restated as the resolution to this specific tension:

- **Minimal-motion** so you keep your map of the map.
- **Gravity** so growth is coherent without a full redraw.
- **Learned ontology** so "better" means better *to you.*

Net: the cartographer redraws *just enough* of the territory to make your new thought fit — never the
whole thing for sport.

**The vision-feedback loop.** The app can screenshot itself, so the agent gets the human "step back and
squint" move: **arrange → look at the render → fix the overlap/imbalance → done.** That loop, not
coordinate math, is where the taste lives. Reuse the existing screenshot capability (S19).

---

## 7. How we might pull it off — *parked for the follow-up*

Three candidate surfaces, decision deferred (this is the explicit next-session topic Max called):

- **In-app chat panel** — native feel, the conversation lives beside the canvas, tight loop with the
  geometry engine. Most product, most build.
- **MCP server** — the canvas exposes the §5 intent verbs as MCP tools; any agent (Claude Code, desktop)
  drives it. Least app UI, leans on existing agents, great for "watch an agent wire up your vault."
- **CLI** — scriptable, headless-testable (fits the zero-dep ethos), but no live conversation.

The intent vocabulary (§5) is the **shared core** under all three — design it once, expose it through
whichever surface(s) win. Likely answer: MCP first (cheapest path to a real agent touching a real vault),
in-app chat as the polished destination.

---

## 8. Rough phasing

1. **The intent vocabulary + resolver** — the §5 verbs, the app turning them into geometry. The spine;
   nothing else works without it. Builds directly on Living Canvas Phase 1 (real links).
2. **Radial layout engine** — hub/spoke/cluster placement, minimal-motion, gravity. The Layer-3 muscle.
3. **First agent surface** (likely MCP) — an agent emitting intents end-to-end on a real folder.
4. **Conversational loop + vision feedback** — talk to it, it screenshots and self-corrects.
5. **Ontology memory** — it learns your clustering preferences across sessions.

---

## 9. The whole thing, in one breath

You **say it**, and a cartographer who knows your whole vault **redraws just enough of the map** to make
your thought fit — **radially, coherently, reversibly** — by **authoring meaning and letting the app
author layout.** Both scaffolds from nothing and tidies a pile, talks while it works, and earns every move
it makes.

---

## 10. Open questions parked for later

- **Surface:** MCP vs in-app chat vs CLI — and whether the §5 verbs are MCP tools or an internal API first.
- **Hub heuristic:** how does the agent *detect* the "obvious center" to promote? Most-linked? Title
  match? Ask once and remember?
- **Minimal-motion metric:** what counts as "enough reason" to move a box? Needs a concrete threshold so
  the agent isn't twitchy.
- **Layout switching:** the cue for radial-vs-columns-vs-grid — does the agent infer it from topology
  (hub-shaped → radial, chain → columns) or does the conversation set it?
- **Conversation ↔ canvas reference:** how does the human name a box mid-chat, and how does the agent show
  which boxes it's about to touch (pulse? highlight?) without an approval dialog.
