# Spec — MCP Server for the Agent Cartographer (v1)

> The "how" for `VISION-agent-cartographer.md` §7. Engineering spec for the **first surface**: an
> **in-app MCP server** that lets an external agent (Claude Code) drive the canvas through the intent
> vocabulary. Grounds every tool on a method that already exists in `AppModel`. Zero new dependencies.

---

## 0. The one decision everything hangs on: the server lives *inside the running app*

Three places the MCP server could live; only one keeps the vision's laws:

| Option | What it is | Verdict |
|---|---|---|
| **In-app HTTP server** | `GraphingApp` listens on `127.0.0.1:<port>`; tools call `AppModel` on the main actor | ✅ **This.** |
| stdio shim process | A separate binary Claude Code spawns, forwarding to the app over a socket | Two processes + an IPC channel to invent. More parts, no gain. |
| Disk-writing process | A standalone server that writes files + `board.json` directly; app catches up via `VaultWatcher` | ❌ Bypasses `transaction{}` → **no undo, no live geometry, no animation.** Breaks three laws at once. |

The decisive reason: the cartographer's whole safety + feel model is **"undo is the preview"** and **"the app
authors layout."** Both only hold if the agent's edits run through the *live* `AppModel.transaction{}` and
the existing geometry (`effectiveFrame`, push-on-drop, auto-grow). So the agent must talk to the running
process, not the disk. Cost we accept: **the app must be open** for the agent to connect (which is also the
"watch it work live" demo, so it's a feature).

---

## 1. Transport — minimal MCP over localhost HTTP

MCP's streamable-HTTP transport, implemented to the **smallest conformant subset**:

- **One endpoint**, `POST /mcp`, body = a JSON-RPC 2.0 message, response = a single `application/json`
  JSON-RPC result. **No SSE, no streaming, no server→client notifications in v1** — every tool is plain
  request/response.
- Methods handled: `initialize`, `tools/list`, `tools/call`. That's the entire protocol surface we need.
- **Bind `127.0.0.1` only** + validate `Origin` (DNS-rebinding guard) + a bearer token written to
  `<vault>/.graphingapp/mcp.json` (`{port, token}`). Loopback is the real fence; the token is belt-and-suspenders.
- Transport built on **`Network.framework` `NWListener`** (TCP) with a hand-rolled HTTP/1.1 parse for the
  one verb we accept. ~one new file, `MCPServer.swift`. No third-party MCP SDK.

```
// ponytail: hand-rolled minimal JSON-RPC-over-HTTP, no SSE. Ceiling: if we need server-pushed
// notifications (live "agent is editing" presence) or the protocol grows, swap to the official
// swift MCP SDK — deferred because today it drags swift-nio into a Command-Line-Tools-only build.
```

**Threading:** `NWListener` fires on a background queue → decode JSON-RPC → `await MainActor.run { dispatch }`
→ `AppModel` runs the mutation on the main actor (SwiftUI requirement) → encode the result back. One hop per
call, no shared mutable state outside the actor.

---

## 2. The tool surface (v1) — every tool is a thin wrapper over an existing method

Addressing: the agent gets node **UUIDs** + `relPath` from `canvas.get`; create-tools return the new UUID.
**Critical:** agent create-calls pass `beginEditing: false` (no inline rename field for a non-human), then
set the title via `rename`.

| MCP tool | Params | Calls | Notes |
|---|---|---|---|
| `canvas.get` | `dir?` | reads `board.nodes` / `board.edges`, `effectiveFrame` | Returns the map the agent reasons over: `[{id, kind, name, relPath, parent, x, y, w, h, expanded, collapsed, pinned}]` + edges `[{from, to, label, linkBacked}]`. Scope to `dir` or whole board. **The eyes.** |
| `canvas.createNote` | `parentDir`, `title` | `addNote(inDir:at:beginEditing:false)` → `rename` | Center is a placeholder; `arrange` fixes position. |
| `canvas.createFolder` | `parentDir`, `title` | `addFolder(...)` → `rename` | |
| `canvas.link` | `from`, `to`, `label?` | `connect(from:to:)` (+ label via edge) | Writes the real `[[wikilink]]` in the managed block **and** the edge — Living Canvas does the disk side. |
| `canvas.move` | `id`, `intoDir` | `move(_:intoDir:)` | Re-files on disk; gravity / re-parenting. |
| `canvas.arrange` | `hubId`, `spokeIds[]`, `style?` | **new** radial resolver (§3) | The Layer-3 call: places spokes around a hub. Default `style: "radial"`. |
| `canvas.expand` / `canvas.collapse` | `id` | `setExpanded(id,true/false)` / `toggleCollapse(id)` | Emphasis (Layer 4). |

```
skipped in v1: canvas.pin (setPinned exists, wire when an agent needs obstacles),
canvas.delete (trust/safety — let the human delete), canvas.screenshot (the vision-feedback
loop — add in v1.1 once the write path is proven), typed-relationship vocab beyond a label.
add when: the agent actually reaches for them.
```

Each tool call already opens its own `transaction{}` inside the called method → **one tool call = one undo
step.** Multi-call "scaffold a whole tree = one ⌘Z" grouping is deferred (would need a public
`batch{}` wrapping `transaction`; add only if the per-call granularity annoys in practice).

---

## 3. The radial resolver (`canvas.arrange`) — the only genuinely new logic

The agent says *"hub = H, spokes = [A,B,C,D]"*; the app computes geometry. v1 is deliberately dumb:

1. Place each spoke on a **circle** around the hub center: `angle = i / n * 2π`, radius `R = max(hub
   half-extent, fitsAllSpokes) + gap`.
2. Set each spoke's center; expand the hub (`setExpanded(hubId, true)`) so it reads as the center.
3. Run the **existing push-on-drop collision solver** (Sprint 5 Lane C) to de-overlap — reuse, don't
   reinvent. Auto-grow + sibling-push already guarantee "nothing overlaps."
4. Whole thing in one `transaction{}` → one undo step for the arrange.

```
// ponytail: circle placement + existing push solver. Ceiling: no force-directed / no crossing-
// minimization. Upgrade to a real graph layout only if radial-of-radial (sub-hubs) visibly tangles.
```

`style` switching (radial → columns/grid per `VISION` §3) is a later branch in the same resolver; v1 ships
radial only, since that's the locked default.

---

## 4. Safety & concurrency (reuse the Living Canvas machinery)

- **Self-write loop:** the agent's edits go *through the app*, so `VaultWatcher` will see them fire. Use the
  **same self-write suppression token** the Living Canvas spec defines (§4.3 / §6) — the agent path is just
  another in-app writer. No new mechanism.
- **Human + agent at once:** agent mutations are main-actor-serialized with the user's input (same actor,
  same `transaction` engine) — they can't interleave mid-mutation. Block-level co-edit niceties are the
  Living Canvas's problem, not this layer's.
- **Auth/exposure:** loopback bind + Origin check + token. The server only starts when a vault is open;
  it stops when the vault closes.

---

## 5. Wiring Claude Code to it

App writes `<vault>/.graphingapp/mcp.json` with the live `{port, token}` on launch. The user (or a generated
`.mcp.json` in the vault) registers it:

```
claude mcp add --transport http graphing-canvas http://127.0.0.1:<port>/mcp \
  --header "Authorization: Bearer <token>"
```

Then in that vault, Claude Code sees `canvas.get`, `canvas.createNote`, `canvas.link`, `canvas.arrange`, …
and can hold a conversation that arranges the real canvas while the user watches.

```
skipped: auto-generating .mcp.json from the app. add when manual `claude mcp add` proves annoying.
```

---

## 6. Walking skeleton (smallest end-to-end), then layers

**Skeleton (the proof):** `MCPServer.swift` answering `initialize` + `tools/list` + `tools/call` for **two**
tools — `canvas.get` and `canvas.createNote` — over localhost HTTP, called from Claude Code, with the new
note appearing live on the canvas and reversible with ⌘Z. That single loop validates transport, the
main-actor hop, undo integration, and the live feel. Everything else is more tools.

1. ✅ **Skeleton** — server + `canvas.get` + `canvas.createNote`. *(Proves the whole pipe.)*
2. ✅ **Connections** — `canvas.link` (reuses `connect`), `canvas.createFolder`, `canvas.move`.
3. ✅ **Placement** — `canvas.arrange` radial resolver (`AppModel.arrangeRadial`) + `canvas.expand` / `canvas.collapse`.
4. ✅ **Conversational scaffold** — a real "mind-map my X" session end-to-end, driven by a headless Claude
   Code agent (`claude -p --mcp-config --strict-mcp-config --dangerously-skip-permissions`).
5. ✅ **Vision-feedback** — `canvas_screenshot` returns the board (or one `dir`) as a PNG (MCP image content)
   via `AppModel.renderBoardPNG` — a schematic in-process render (folders → edges → notes z-order, no
   screen-recording permission). The agent can now *see its own layout and self-correct*.

> **Status (2026-06-23):** **phases 1–5 all built and verified live** against the `Graph test` vault. All 8 tools
> work end-to-end (renamed to snake_case — `canvas_get`, … — since the Anthropic tool-name charset forbids
> dots). `arrange` lays a perfect ring; `link` writes the real `<!-- canvas-links -->` block; `move` refiles
> on disk. **Phase 4 proof:** a headless Claude Code agent, given only "mind-map a two-week Japan trip" + the
> MCP config (from the running app's `mcp.json`), created a `Japan Trip/` folder + hub + 6 self-chosen
> branches (Itinerary/Accommodation/Food/Transport/Budget/Culture), linked them (6 `[[wikilinks]]` in
> `Japan Trip.md`), and arranged a clean hexagon (d=352, 60° apart, hub expanded). **Phase 5 proof:**
> `canvas_screenshot` rendered that hexagon to a valid PNG — hub + 6 spokes + all 6 connectors visible
> (after fixing a z-order bug where the folder fill hid the edges). The render also surfaced a real layout
> flaw (folder frame extends well below its content) — exactly the signal the feedback loop exists to give.
> **9 tools now.** Next: real cartographer behaviors (gravity, minimal-motion, layout-switching) per VISION.
>
> **Wiring recipe:** app writes `<vault>/.graphingapp/mcp.json` (`{port, token}`) on open → build a
> `--mcp-config` JSON (`{"mcpServers":{"graphing-canvas":{"type":"http","url":"http://127.0.0.1:<port>/mcp",
> "headers":{"Authorization":"Bearer <token>"}}}}`) → `claude -p "<task>" --mcp-config cfg.json
> --strict-mcp-config --dangerously-skip-permissions`. Tools surface to the model as
> `mcp__graphing-canvas__canvas_*`.

---

## 7. Open questions parked

- **Undo granularity:** is one-undo-step-per-tool-call right, or do users want one ⌘Z to reverse a whole
  agent turn? (Driven by how chatty real sessions are — measure before adding `batch{}`.)
- **Port stability:** fixed port vs ephemeral-written-to-`mcp.json`. Ephemeral is safer; does Claude Code's
  static `.mcp.json` tolerate a changing URL? May force a fixed default port with fallback.
- **`canvas.get` payload size:** whole-vault boards could be large. Does the agent always scope to a `dir`,
  or do we need a summarized/altitude-aware read (constellations, not every leaf)? Ties to VISION §3 altitude.
- **Naming collisions:** `createNote` → `rename` can hit `uniqueRel` / existing-name beeps. Tool must
  return a clear error the agent can react to, not a silent no-op.
- **Token rotation / multi-vault:** one server per open vault, or one server multiplexing? v1 = one open
  vault, one server.
