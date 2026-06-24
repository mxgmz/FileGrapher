import Foundation
import Network
import CoreGraphics

/// In-app MCP server — the first surface for the Agent Cartographer (see docs/SPEC-mcp-cartographer.md).
/// An external agent (Claude Code) drives the canvas through tools that are thin wrappers over the same
/// `AppModel` mutations the UI uses, so every agent edit flows through `transaction{}` → one ⌘Z reverses it.
///
/// v1 is the *walking skeleton*: minimal MCP-over-HTTP on loopback, two tools (`canvas.get`,
/// `canvas.createNote`). No SSE, no sessions, no streaming notifications.
/// ponytail: hand-rolled minimal JSON-RPC-over-HTTP, no MCP SDK (keeps the zero-dep, CLT-only build).
/// Ceiling: if we need server-pushed notifications or sessions, swap to the official swift MCP SDK.
final class MCPServer {
    private var listener: NWListener?
    private weak var model: AppModel?
    // Captured at start() (on the main actor) so the background listener callbacks can write mcp.json
    // without reaching back into main-actor `AppModel` state.
    private var vaultRef: Vault?
    private var infoFileURL: URL?
    private var token = ""
    private let queue = DispatchQueue(label: "mcp.server")

    /// Start (or restart) the server for the currently open vault. Writes `{port, token}` to
    /// `<vault>/.graphingapp/mcp.json` once the port is assigned, so the user can `claude mcp add` it.
    @MainActor func start(model: AppModel) {
        stop()
        self.model = model
        vaultRef = model.vault
        infoFileURL = model.vault?.root.appendingPathComponent(".graphingapp/mcp.json")
        token = UUID().uuidString
        do {
            let params = NWParameters.tcp
            // Loopback-only bind is the real fence; the bearer token is belt-and-suspenders.
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state, let port = listener.port?.rawValue { self?.writeInfo(port: port) }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            Log.disk.error("MCP server failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        if let url = infoFileURL { try? FileManager.default.removeItem(at: url) }
    }

    private func writeInfo(port: UInt16) {
        guard let vault = vaultRef, let url = infoFileURL else { return }
        vault.ensureAppDir()
        let info: [String: Any] = ["port": Int(port), "token": token]
        try? JSONSerialization.data(withJSONObject: info, options: .prettyPrinted).write(to: url, options: .atomic)
        Log.disk.info("MCP server listening on 127.0.0.1:\(port, privacy: .public)")
    }

    // MARK: HTTP

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if let request = HTTPRequest(buffer), request.isComplete {
                self.respond(to: request, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        func send(_ status: String, _ json: Any?) {
            var body = Data()
            if let json { body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data() }
            var head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\n"
            head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            var out = Data(head.utf8); out.append(body)
            connection.send(content: out, completion: .contentProcessed { _ in connection.cancel() })
        }

        guard request.method == "POST", request.path == "/mcp" else { return send("404 Not Found", nil) }
        guard request.headers["authorization"] == "Bearer \(token)" else { return send("401 Unauthorized", nil) }
        guard let message = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
            return send("400 Bad Request", nil)
        }
        let method = message["method"] as? String ?? ""
        // A JSON-RPC notification has no `id` and gets no body back.
        guard let id = message["id"] else { return send("202 Accepted", nil) }

        dispatch(method, params: message["params"] as? [String: Any] ?? [:]) { result in
            switch result {
            case .success(let value): send("200 OK", ["jsonrpc": "2.0", "id": id, "result": value])
            case .failure(let error): send("200 OK", ["jsonrpc": "2.0", "id": id, "error": ["code": -32603, "message": error.message]])
            }
        }
    }

    // MARK: JSON-RPC

    private func dispatch(_ method: String, params: [String: Any], reply: @escaping (Result<Any, ToolError>) -> Void) {
        switch method {
        case "initialize":
            reply(.success([
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "graphing-canvas", "version": "0.1.0"],
            ]))
        case "tools/list":
            reply(.success(["tools": Self.toolSchemas]))
        case "tools/call":
            callTool(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:], reply)
        default:
            reply(.failure(ToolError("Unknown method: \(method)")))
        }
    }

    /// Tool bodies hop to the main actor — `AppModel` is SwiftUI state, every mutation must run there.
    private func callTool(_ name: String, _ args: [String: Any], _ reply: @escaping (Result<Any, ToolError>) -> Void) {
        Task { @MainActor [weak model] in
            guard let model else { return reply(.failure(ToolError("App model unavailable"))) }
            switch name {
            case "canvas_get":
                let depth = max(1, (args["depth"] as? Int) ?? 1)
                let maxNodes = max(1, (args["maxNodes"] as? Int) ?? 800)
                reply(.success(Self.toolText(Self.boardJSON(model, dir: args["dir"] as? String, depth: depth, maxNodes: maxNodes))))

            case "canvas_health":
                let data = (try? JSONSerialization.data(withJSONObject: model.boardHealth(), options: [.prettyPrinted, .sortedKeys])) ?? Data()
                reply(.success(Self.toolText(String(data: data, encoding: .utf8) ?? "{}")))

            case "canvas_read":
                let ids = (args["ids"] as? [Any])?.compactMap { $0 as? String }
                let depth = max(1, (args["depth"] as? Int) ?? 1)
                let maxNotes = max(1, (args["maxNotes"] as? Int) ?? 25)
                let maxChars = max(1, (args["maxChars"] as? Int) ?? 2000)
                reply(.success(Self.toolText(Self.readJSON(model, ids: ids, dir: args["dir"] as? String, depth: depth, maxNotes: maxNotes, maxChars: maxChars))))

            case "canvas_create_note":
                guard model.vault != nil else { return reply(.failure(ToolError("No vault is open"))) }
                let dir = args["parentDir"] as? String ?? ""
                let title = (args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                // Placeholder scatter so two quick creates don't stack exactly; `canvas.arrange` will own
                // real placement once it lands.
                let count = model.board.nodes.count
                let center = CGPoint(x: CGFloat(count % 5) * 180, y: CGFloat(count / 5) * 120)
                guard let newId = model.addNote(inDir: dir, at: center, beginEditing: false) else {
                    return reply(.failure(ToolError("Could not create note (check parentDir)")))
                }
                if !title.isEmpty { model.rename(newId, to: title) }
                let rel = model.node(newId)?.relPath ?? ""
                reply(.success(Self.toolText("Created note \"\(title)\" → \(rel)\nid: \(newId.uuidString)")))

            case "canvas_create_folder":
                guard model.vault != nil else { return reply(.failure(ToolError("No vault is open"))) }
                let dir = args["parentDir"] as? String ?? ""
                let title = (args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let count = model.board.nodes.count
                let center = CGPoint(x: CGFloat(count % 5) * 220, y: CGFloat(count / 5) * 160)
                guard let newId = model.addFolder(inDir: dir, at: center, beginEditing: false) else {
                    return reply(.failure(ToolError("Could not create folder (check parentDir)")))
                }
                if !title.isEmpty { model.rename(newId, to: title) }
                let rel = model.node(newId)?.relPath ?? ""
                reply(.success(Self.toolText("Created folder \"\(title)\" → \(rel)\nid: \(newId.uuidString)")))

            case "canvas_link":
                guard let from = Self.uuid(args["from"]), let to = Self.uuid(args["to"]) else {
                    return reply(.failure(ToolError("link needs 'from' and 'to' node ids")))
                }
                guard model.connect(from: from, to: to) else {
                    return reply(.failure(ToolError("Could not link (same node, missing box, or already linked)")))
                }
                // Gravity (VISION §4 law 3): in the common create-then-link gesture, `from` is the fresh note.
                // If this is its *only* edge it hasn't found its neighborhood yet — pull it beside its kin.
                let firstLink = model.board.edges.filter { $0.from == from || $0.to == from }.count == 1
                if firstLink, model.node(from)?.kind == .note { model.placeNearKin(newNode: from, anchor: to) }
                reply(.success(Self.toolText("Linked \(from.uuidString) → \(to.uuidString) — wrote the [[wikilink]]")))

            case "canvas_write":
                guard let id = Self.uuid(args["id"]), let target = model.node(id) else {
                    return reply(.failure(ToolError("write needs a valid 'id'")))
                }
                guard target.kind != .folder else {
                    return reply(.failure(ToolError("Folders have no content; write to a note (e.g. a folder-note).")))
                }
                guard !model.isTimeTraveling else {
                    return reply(.failure(ToolError("Can't write while viewing history")))
                }
                // Honor the no-prose-clobber law: only ever touch the app-managed canvas-note block.
                let text = args["text"] as? String ?? ""
                model.saveFileContent(id, ManagedLinks.writeNote(text, into: model.fileText(id)))
                reply(.success(Self.toolText(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Cleared \(target.name)'s canvas-note block"
                    : "Wrote \(text.count) chars into \(target.name)'s canvas-note block — your prose untouched")))

            case "canvas_move":
                guard let id = Self.uuid(args["id"]), let target = model.node(id) else {
                    return reply(.failure(ToolError("move needs a valid 'id'")))
                }
                model.move(id, intoDir: args["intoDir"] as? String ?? "")
                reply(.success(Self.toolText("Moved \(target.name) → \(model.node(id)?.relPath ?? target.relPath)")))

            case "canvas_arrange":
                guard let hub = Self.uuid(args["hubId"]), model.node(hub) != nil else {
                    return reply(.failure(ToolError("arrange needs a valid 'hubId'")))
                }
                let spokes = (args["spokeIds"] as? [Any] ?? []).compactMap { Self.uuid($0) }
                guard !spokes.isEmpty else { return reply(.failure(ToolError("arrange needs a non-empty 'spokeIds'"))) }
                // Layout-switching ("per topology"): an explicit radial/grid/columns, or "auto" (default) to
                // pick from the link graph. Minimal-motion either way (unchanged-enough boxes stay put).
                let layoutArg = (args["layout"] as? String)?.lowercased() ?? "auto"
                let layout = AppModel.ArrangeLayout(rawValue: layoutArg) ?? model.autoLayout(hub: hub, spokes: spokes)
                model.arrange(hub: hub, spokes: spokes, layout: layout)
                reply(.success(Self.toolText("Arranged \(spokes.count) spoke(s) in a \(layout.rawValue) layout (unchanged-enough boxes left put).")))

            case "canvas_expand", "canvas_collapse":
                guard let id = Self.uuid(args["id"]), let target = model.node(id) else {
                    return reply(.failure(ToolError("\(name) needs a valid 'id'")))
                }
                let open = name == "canvas_expand"
                if target.kind == .folder {
                    // Folder: collapse hides its children (header + count), expand shows them.
                    if open == target.isCollapsedFolder { model.toggleCollapse(id) }
                } else {
                    model.setExpanded(id, open)   // Note: show/hide its content card.
                }
                reply(.success(Self.toolText("\(open ? "Expanded" : "Collapsed") \(target.name)")))

            case "canvas_resize":
                guard let id = Self.uuid(args["id"]), let target = model.node(id) else {
                    return reply(.failure(ToolError("resize needs a valid 'id'")))
                }
                let w = (args["width"] as? NSNumber)?.doubleValue ?? target.width
                let h = (args["height"] as? NSNumber)?.doubleValue ?? target.height
                model.setSize(id, CGSize(width: w, height: h))
                reply(.success(Self.toolText("Resized \(target.name) to \(Int(w))×\(Int(h))")))

            case "canvas_color":
                let ids = Set((args["ids"] as? [Any] ?? [args["id"] as Any]).compactMap { Self.uuid($0) })
                guard !ids.isEmpty else { return reply(.failure(ToolError("color needs 'ids' (array) or 'id'"))) }
                let raw = (args["color"] as? String ?? "").lowercased()
                let clearing = raw.isEmpty || raw == "none"
                let color = clearing ? nil : BoxColor(rawValue: raw)
                if !clearing, color == nil {
                    return reply(.failure(ToolError("unknown color '\(raw)' — use: blue purple pink red orange yellow green teal graphite, or none")))
                }
                model.setColor(ids, color)
                reply(.success(Self.toolText("Colored \(ids.count) box(es) \(clearing ? "default" : raw)")))

            case "canvas_screenshot":
                guard let png = model.renderBoardPNG(scope: args["dir"] as? String) else {
                    return reply(.failure(ToolError("Nothing to render (empty board or unknown dir)")))
                }
                reply(.success(["content": [["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"]]]))

            default:
                reply(.failure(ToolError("Unknown tool: \(name)")))
            }
        }
    }

    // MARK: Tool payloads

    /// Wrap a string as an MCP `tools/call` text-content result.
    private static func toolText(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]]]
    }

    private static func uuid(_ value: Any?) -> UUID? {
        (value as? String).flatMap { UUID(uuidString: $0) }
    }

    /// The map the agent reasons over — nodes + edges as a JSON string. Optionally scoped to one folder,
    /// `depth` levels deep (1 == direct children, the default), and capped at `maxNodes` so a huge vault
    /// can be read altitude-by-altitude instead of as one giant payload (the parked big-vault concern).
    /// When the scope yields more than `maxNodes`, the result is truncated and flagged `truncated: true`.
    @MainActor private static func boardJSON(_ model: AppModel, dir: String?, depth: Int = 1, maxNodes: Int = 800) -> String {
        let matched = scopedNodes(model, dir: dir, depth: depth)
        let nodes: [[String: Any]] = matched.prefix(maxNodes).map { node in
            [
                "id": node.id.uuidString, "kind": node.kind.rawValue, "name": node.name,
                "relPath": node.relPath, "parent": node.parentRel,
                "x": node.x, "y": node.y, "w": node.width, "h": node.height,
                "expanded": node.isExpanded, "collapsed": node.isCollapsedFolder, "pinned": node.isPinned,
            ]
        }
        // Only edges between two returned nodes (so a scoped/capped read stays self-consistent).
        let shownIds = Set(matched.prefix(maxNodes).map(\.id))
        let edges: [[String: Any]] = model.board.edges
            .filter { shownIds.contains($0.from) && shownIds.contains($0.to) }
            .map { edge in
                [
                    "from": edge.from.uuidString, "to": edge.to.uuidString,
                    "label": edge.label ?? "", "linkBacked": edge.linkBacked ?? false,
                ]
            }
        let payload: [String: Any] = [
            "nodes": nodes, "edges": edges,
            "totalInScope": matched.count, "truncated": matched.count > maxNodes,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Nodes within `dir` (nil/empty = whole board), `depth` levels deep (1 = direct children). Shared by
    /// `boardJSON` (canvas_get) and `readJSON` (canvas_read) so both scope by one rule.
    @MainActor private static func scopedNodes(_ model: AppModel, dir: String?, depth: Int) -> [BoardNode] {
        guard let scope = (dir?.isEmpty == false) ? dir : nil else { return model.board.nodes }
        return model.board.nodes.filter { node in
            if node.parentRel == scope { return true }                      // direct child
            guard node.relPath.hasPrefix(scope + "/") else { return false }  // not under the scope at all
            let below = node.relPath.dropFirst(scope.count + 1).split(separator: "/").count
            return below <= depth                                            // within `depth` levels under scope
        }
    }

    /// Perception: the actual *content* of notes plus their intended link graph — what `canvas_get`
    /// (layout only) can't see. Selected by explicit `ids` or by `dir`/`depth` scope; folders are skipped
    /// (no content). Each note's text is capped at `maxChars` and the set at `maxNotes` to bound the
    /// payload (`chars`/`truncated` flag what was cut). `links` is every `[[wikilink]]` in the *full*
    /// text, so the intended graph survives the content cap. Read-only — never writes a file.
    @MainActor private static func readJSON(_ model: AppModel, ids: [String]?, dir: String?, depth: Int, maxNotes: Int, maxChars: Int) -> String {
        let scoped: [BoardNode]
        if let ids, !ids.isEmpty {                                          // explicit selection wins over scope
            let wanted = Set(ids.compactMap { UUID(uuidString: $0) })
            scoped = model.board.nodes.filter { wanted.contains($0.id) }
        } else {
            scoped = scopedNodes(model, dir: dir, depth: depth)
        }
        let readable = scoped.filter { $0.kind != .folder }
        let notes: [[String: Any]] = readable.prefix(maxNotes).map { node in
            let full = model.fileText(node.id)
            let truncated = full.count > maxChars
            return [
                "id": node.id.uuidString, "kind": node.kind.rawValue, "name": node.name,
                "relPath": node.relPath,
                "text": truncated ? String(full.prefix(maxChars)) : full,
                "chars": full.count, "truncated": truncated,
                "links": ManagedLinks.wikilinkTargets(in: full),
            ]
        }
        let payload: [String: Any] = [
            "notes": notes,
            "totalInScope": readable.count, "truncated": readable.count > maxNotes,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static let toolSchemas: [[String: Any]] = [
        [
            "name": "canvas_get",
            "description": "Read the canvas: every box (id, kind, name, path, position, size, state) and every connector. Scope to one folder (`dir`), `depth` levels deep, capped at `maxNodes` — the result reports `totalInScope` and `truncated` so a huge vault can be read altitude-by-altitude.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "dir": ["type": "string", "description": "Vault-relative folder path to scope to; omit for the whole board."],
                    "depth": ["type": "integer", "description": "Levels below `dir` to include (1 = direct children, the default)."],
                    "maxNodes": ["type": "integer", "description": "Cap on returned boxes (default 800); the result flags `truncated` when exceeded."],
                ],
            ],
        ],
        [
            "name": "canvas_health",
            "description": "Gardening diagnostic — structural signals the canvas is drifting out of legibility: orphan notes (no connectors), crowded folders, overlapping sibling boxes, and visual-only connectors (not real [[links]]). Read-only; use it to decide what to tidy, then act with arrange/move/link/collapse.",
            "inputSchema": ["type": "object"],
        ],
        [
            "name": "canvas_read",
            "description": "Perception — read what notes actually say (content) plus their intended link graph, which canvas_get (layout only) can't see. Select boxes by `ids` (e.g. the orphans canvas_health flagged) or by `dir`/`depth` scope. Each note returns capped `text` (with `chars`/`truncated`) and `links` (every [[wikilink]] in the full text). Use this to group or link notes BY MEANING. Read-only; never edits a file.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "ids": ["type": "array", "items": ["type": "string"], "description": "Box ids to read; takes precedence over dir/depth. Omit to read by scope."],
                    "dir": ["type": "string", "description": "Vault-relative folder to scope to (when no `ids`); omit for the whole board."],
                    "depth": ["type": "integer", "description": "Levels below `dir` to include (1 = direct children, the default)."],
                    "maxNotes": ["type": "integer", "description": "Cap on returned notes (default 25); the result flags `truncated` when exceeded."],
                    "maxChars": ["type": "integer", "description": "Per-note content cap (default 2000); each note flags its own `truncated`."],
                ],
            ],
        ],
        [
            "name": "canvas_create_note",
            "description": "Create a new .md note on disk and a box for it on the canvas. Reversible with one ⌘Z.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "The note's title (also its filename)."],
                    "parentDir": ["type": "string", "description": "Vault-relative folder to create it in; omit for the vault root."],
                ],
                "required": ["title"],
            ],
        ],
        [
            "name": "canvas_create_folder",
            "description": "Create a new folder (real directory) and a box for it on the canvas.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "The folder's name."],
                    "parentDir": ["type": "string", "description": "Vault-relative parent folder; omit for the vault root."],
                ],
                "required": ["title"],
            ],
        ],
        [
            "name": "canvas_link",
            "description": "Connect two boxes: draws a directed edge AND writes a real [[wikilink]] from 'from' to 'to'.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "from": ["type": "string", "description": "Source box id (the file that gets the [[wikilink]])."],
                    "to": ["type": "string", "description": "Target box id."],
                ],
                "required": ["from", "to"],
            ],
        ],
        [
            "name": "canvas_write",
            "description": "Authoring — write prose (a summary, a map-of-content, a folder-note body) INTO a note's app-managed `<!-- canvas-note -->` block. The user's OWN prose is never touched: this only creates/replaces/removes that one fenced block, and re-running replaces it (idempotent — safe to re-summarize). Pass empty `text` to clear it. Pair with canvas_create_note to make a fresh note, then fill it. Folders have no content. Undoable with one ⌘Z.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Box id of the note to write into."],
                    "text": ["type": "string", "description": "Markdown to place in the managed note block; empty/omitted clears it."],
                ],
                "required": ["id"],
            ],
        ],
        [
            "name": "canvas_move",
            "description": "Re-file a box into another folder (moves the real file/directory on disk).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Box id to move."],
                    "intoDir": ["type": "string", "description": "Destination folder (vault-relative); omit for the vault root."],
                ],
                "required": ["id"],
            ],
        ],
        [
            "name": "canvas_arrange",
            "description": "Lay spokes out around a hub box (and expand the hub) in a chosen layout. The app owns placement — you supply intent, not coordinates. Minimal-motion: boxes already in place don't move.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "hubId": ["type": "string", "description": "The box at the center / anchor."],
                    "spokeIds": ["type": "array", "items": ["type": "string"], "description": "Boxes to arrange around the hub."],
                    "layout": ["type": "string", "enum": ["auto", "radial", "grid", "columns"], "description": "How to lay them out: 'auto' (default) picks per link topology; 'radial' ring; 'grid' block of peers; 'columns' stack for a sequence."],
                ],
                "required": ["hubId", "spokeIds"],
            ],
        ],
        [
            "name": "canvas_expand",
            "description": "Show a box's content as an in-place card (the 'loud' emphasis state).",
            "inputSchema": ["type": "object", "properties": ["id": ["type": "string"]], "required": ["id"]],
        ],
        [
            "name": "canvas_collapse",
            "description": "Collapse a box back to a title-only chip (the 'quiet' emphasis state).",
            "inputSchema": ["type": "object", "properties": ["id": ["type": "string"]], "required": ["id"]],
        ],
        [
            "name": "canvas_resize",
            "description": "Resize a box (visual only — never touches the file). Good for making a hub or key note bigger.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "width": ["type": "number"], "height": ["type": "number"],
                ],
                "required": ["id"],
            ],
        ],
        [
            "name": "canvas_color",
            "description": "Color-code boxes (visual only). Pass 'ids' (array) or a single 'id', and a 'color': blue, purple, pink, red, orange, yellow, green, teal, graphite, or 'none' to clear.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "ids": ["type": "array", "items": ["type": "string"]],
                    "id": ["type": "string"],
                    "color": ["type": "string"],
                ],
                "required": ["color"],
            ],
        ],
        [
            "name": "canvas_screenshot",
            "description": "Render the canvas (or one folder via 'dir') to a PNG so you can SEE the layout and self-correct — check for overlaps, balance, and clustering, then adjust. Schematic: boxes + titles + connectors.",
            "inputSchema": [
                "type": "object",
                "properties": ["dir": ["type": "string", "description": "Vault-relative folder to render; omit for the whole board."]],
            ],
        ],
    ]
}

// MARK: Cartographer laws (VISION-agent-cartographer.md §4) — gravity + minimal-motion
//
// These live as an `extension AppModel` in the same module so the Model.swift core stays untouched: both
// are thin compositions of existing geometry (nearestFreeCenter / the push solver / worldFrame), never new
// layout math. The MCP tools call them; the app gets them for free if it ever wants them.
extension AppModel {
    /// Gravity (law 3): a freshly-linked note should land *near its kin*, not at a scatter slot. Place
    /// `newNode` at the nearest free center adjacent to `anchor`, reusing `nearestFreeCenter` so it never
    /// overlaps an occupied slot. The seed sits one box-gap to the anchor's right (in world space); the
    /// ring-scan finds the closest real gap from there. World→relative conversion goes through the same
    /// chokepoint every write path uses, so nested folders stay correct.
    func placeNearKin(newNode: UUID, anchor: UUID) {
        guard let new = node(newNode), let kin = node(anchor) else { return }
        let kinFrame = worldFrame(of: kin)
        let gap = AppModel.gridStep
        let seedWorld = CGPoint(x: kinFrame.maxX + gap + new.width / 2, y: kinFrame.midY)
        let seedRelative = relativeCenter(seedWorld, inDir: new.parentRel)   // nearestFreeCenter reasons in parent-relative space
        let free = nearestFreeCenter(for: newNode, near: seedRelative) ?? seedRelative
        transaction { setPosition(newNode, to: free) }   // one ⌘Z reverses the gravity nudge
    }

    /// The layouts the cartographer can switch between *per topology* (the agent-cartographer
    /// "layout-switching" behavior / VISION-folder-canvas §5): a hub-and-spoke `radial` ring, a flat
    /// `grid` of peers, or a `columns` stack for a sequence. `autoLayout` picks one from the link graph.
    enum ArrangeLayout: String { case radial, grid, columns }

    /// Arrange `spokeIds` around `hub` in the given `layout`, **minimal-motion**: each spoke is matched to
    /// its nearest target slot and only moved if it's farther than `arrangeSettleRadius` (so re-running a
    /// tidy layout is a no-op), then overlaps settle. The placement is shared across all three layouts —
    /// only the slot geometry differs. One undoable step.
    func arrange(hub hubId: UUID, spokes spokeIds: [UUID], layout: ArrangeLayout) {
        guard node(hubId) != nil, !spokeIds.isEmpty else { return }
        transaction {
            setExpanded(hubId, true)
            guard let hub = node(hubId) else { return }   // re-read: expanding can resize the card
            let slots: [CGPoint]
            switch layout {
            case .radial:  slots = radialSlots(around: hub, spokes: spokeIds)
            case .grid:    slots = gridSlots(around: hub, spokes: spokeIds)
            case .columns: slots = columnSlots(around: hub, spokes: spokeIds)
            }
            for (spoke, slot) in AppModel.assignToNearestSlots(spokeIds, slots, center: { self.node($0)?.center }) {
                guard let current = node(spoke)?.center else { continue }
                if hypot(slot.x - current.x, slot.y - current.y) > AppModel.arrangeSettleRadius {
                    setPosition(spoke, to: slot)   // far enough to be worth moving; otherwise leave it put
                    // ponytail: setPosition (== post-migration moveSubtree) — children store relative, so they ride along.
                }
            }
            resolveOverlaps(movedId: hubId)
        }
    }

    /// Back-compat shim — radial was the only layout the original call site used.
    func arrangeRadialMinimalMotion(hub hubId: UUID, spokes spokeIds: [UUID]) {
        arrange(hub: hubId, spokes: spokeIds, layout: .radial)
    }

    /// Pick a layout from the link topology (the cartographer's "per topology" smarts): a hub linked to
    /// most of its spokes → `radial`; else a chain through the spokes → `columns`; else a flat set →
    /// `grid`. ponytail: a coarse heuristic on edge counts — the agent can always override via `layout`.
    func autoLayout(hub hubId: UUID, spokes spokeIds: [UUID]) -> ArrangeLayout {
        let spokeSet = Set(spokeIds)
        let linkedToHub = Set(board.edges.compactMap { edge -> UUID? in
            if edge.from == hubId, spokeSet.contains(edge.to) { return edge.to }
            if edge.to == hubId, spokeSet.contains(edge.from) { return edge.from }
            return nil
        })
        if linkedToHub.count >= max(2, (spokeIds.count + 1) / 2) { return .radial }   // genuine hub-and-spoke
        let interSpoke = board.edges.filter { spokeSet.contains($0.from) && spokeSet.contains($0.to) }.count
        if spokeIds.count >= 3, interSpoke >= spokeIds.count - 1 { return .columns }  // a chain / sequence
        return .grid
    }

    /// Hub radius (half its larger side) — shared spacing input.
    private func hubReach(_ hub: BoardNode) -> CGFloat { let f = effectiveFrame(of: hub); return max(f.width, f.height) / 2 }
    /// Largest spoke half-extent — the other shared spacing input.
    private func spokeReach(_ spokes: [UUID]) -> CGFloat {
        spokes.compactMap { node($0) }.map { max($0.width, $0.height) / 2 }.max() ?? 0
    }

    /// Radial: an evenly-spaced ring around the hub, first slot at 12 o'clock; radius sized so neither the
    /// hub nor crowded spokes overlap. (The geometry Lane C shipped, now one layout among three.)
    private func radialSlots(around hub: BoardNode, spokes spokeIds: [UUID]) -> [CGPoint] {
        let center = hub.center, reach = spokeReach(spokeIds), gap: CGFloat = 80
        let radius = max(hubReach(hub) + reach + gap, CGFloat(spokeIds.count) * (reach * 2 + gap) / (2 * .pi))
        return (0..<spokeIds.count).map { i in
            let angle = Double(i) / Double(spokeIds.count) * 2 * .pi - .pi / 2
            return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
        }
    }

    /// Grid: a roughly-square block of cells centered under the hub (row-major) — a flat set of peers.
    private func gridSlots(around hub: BoardNode, spokes spokeIds: [UUID]) -> [CGPoint] {
        let reach = spokeReach(spokeIds), gap: CGFloat = 80, cell = reach * 2 + gap
        let count = spokeIds.count
        let cols = max(1, Int(ceil(Double(count).squareRoot())))
        let firstY = hub.center.y + hubReach(hub) + gap + reach          // first row just below the hub
        let startX = hub.center.x - CGFloat(cols - 1) * cell / 2          // block centered on the hub
        return (0..<count).map { i in
            CGPoint(x: startX + CGFloat(i % cols) * cell, y: firstY + CGFloat(i / cols) * cell)
        }
    }

    /// Columns: a single vertical stack directly below the hub — a sequence / list.
    private func columnSlots(around hub: BoardNode, spokes spokeIds: [UUID]) -> [CGPoint] {
        let reach = spokeReach(spokeIds), gap: CGFloat = 80, cell = reach * 2 + gap
        let firstY = hub.center.y + hubReach(hub) + gap + reach
        return (0..<spokeIds.count).map { i in CGPoint(x: hub.center.x, y: firstY + CGFloat(i) * cell) }
    }

    /// A folder with more direct children than this reads as crowded — a candidate to sub-organize.
    static let crowdedFolderLimit = 12

    /// Read-only **gardening** diagnostic (the cartographer's custodial sense): structural signals that a
    /// canvas is drifting out of legibility, computed purely from the board — no content read. The agent
    /// calls this to decide *what* to tidy, then acts with the existing arrange/move/link/collapse tools.
    /// - `orphans`: notes with no connector at all.
    /// - `crowdedFolders`: folders past `crowdedFolderLimit` direct children.
    /// - `overlaps`: visible sibling boxes whose drawn frames intersect (residual collisions to push apart).
    /// - `unbackedConnectors`: note↔note edges not backed by a real `[[link]]` on disk (visual-only).
    /// (A content-aware signal — prose `[[links]]` written but not yet drawn — needs a read-content tool; deferred.)
    func boardHealth() -> [String: Any] {
        func ref(_ n: BoardNode) -> [String: Any] { ["id": n.id.uuidString, "name": n.name, "relPath": n.relPath] }

        let linked = Set(board.edges.flatMap { [$0.from, $0.to] })
        let orphans = board.nodes.filter { $0.kind == .note && !linked.contains($0.id) }

        let crowded = board.nodes.filter { $0.kind == .folder }.compactMap { folder -> [String: Any]? in
            let children = board.nodes.filter { $0.parentRel == folder.relPath }.count
            guard children > AppModel.crowdedFolderLimit else { return nil }
            return ["id": folder.id.uuidString, "name": folder.name, "relPath": folder.relPath, "childCount": children]
        }

        // Overlaps matter only among VISIBLE siblings (a collapsed folder hides its children; children of
        // different folders can't overlap in the layout sense). O(n²) per sibling group — fine at this
        // scale; the reported list is capped below.
        let hidden = hiddenNodeIds
        let groups = Dictionary(grouping: board.nodes.filter { !hidden.contains($0.id) }) { $0.parentRel }
        var overlaps: [[String: Any]] = []
        for (_, siblings) in groups where siblings.count > 1 {
            for i in 0..<siblings.count {
                let fi = effectiveFrame(of: siblings[i])
                for j in (i + 1)..<siblings.count where fi.intersects(effectiveFrame(of: siblings[j])) {
                    overlaps.append(["a": siblings[i].name, "aId": siblings[i].id.uuidString,
                                     "b": siblings[j].name, "bId": siblings[j].id.uuidString])
                }
            }
        }

        let noteIds = Set(board.nodes.filter { $0.kind == .note }.map { $0.id })
        let unbacked = board.edges.filter { !($0.linkBacked ?? false) && noteIds.contains($0.from) && noteIds.contains($0.to) }

        return [
            "orphans": orphans.prefix(100).map(ref), "orphanCount": orphans.count,
            "crowdedFolders": crowded,
            "overlaps": Array(overlaps.prefix(100)), "overlapCount": overlaps.count,
            "unbackedConnectors": unbacked.prefix(100).map { ["from": $0.from.uuidString, "to": $0.to.uuidString] },
            "unbackedConnectorCount": unbacked.count,
        ]
    }

    /// A spoke already this close (world units) to its target slot is "tidy enough" — leave it put rather
    /// than nudge it. ~½ a grid step: small enough that the ring still reads even, big enough that a re-run
    /// on an already-arranged hub is a no-op (no twitch). ponytail: a flat threshold is the first cut.
    static let arrangeSettleRadius: CGFloat = 24

    /// Greedily pair each spoke to its nearest free target slot (cheap reduction of total motion vs. a fixed
    /// index→slot mapping). Pure + static so it's portable to the headless harness. `center` resolves a
    /// spoke's current center; a spoke with no center falls back to a leftover slot in order.
    static func assignToNearestSlots(_ spokes: [UUID], _ slots: [CGPoint],
                                     center: (UUID) -> CGPoint?) -> [(UUID, CGPoint)] {
        var remaining = Array(slots.enumerated())
        var pairs: [(UUID, CGPoint)] = []
        for spoke in spokes {
            guard let here = center(spoke), let pick = remaining.enumerated().min(by: {
                hypot($0.element.element.x - here.x, $0.element.element.y - here.y) <
                hypot($1.element.element.x - here.x, $1.element.element.y - here.y)
            }) else {
                if !remaining.isEmpty { pairs.append((spoke, remaining.removeFirst().element)) }
                continue
            }
            pairs.append((spoke, pick.element.element))
            remaining.remove(at: pick.offset)
        }
        return pairs
    }
}

/// A tool failure carrying a human-readable message (becomes the JSON-RPC error message).
private struct ToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// A parsed HTTP/1.1 request, just enough of one for our single `POST /mcp` endpoint.
private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    let isComplete: Bool   // false until the full Content-Length body has arrived

    init?(_ raw: Data) {
        guard let separator = raw.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: raw[..<separator.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.first?.components(separatedBy: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        method = requestLine[0]
        path = requestLine[1]

        var parsed: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            parsed[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        headers = parsed

        let available = raw[separator.upperBound...]
        let expected = Int(parsed["content-length"] ?? "0") ?? 0
        body = Data(available.prefix(expected))
        isComplete = available.count >= expected
    }
}
