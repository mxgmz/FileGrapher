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
                reply(.success(Self.toolText(Self.boardJSON(model, dir: args["dir"] as? String))))

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
                reply(.success(Self.toolText("Linked \(from.uuidString) → \(to.uuidString) — wrote the [[wikilink]]")))

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
                model.arrangeRadial(hub: hub, spokes: spokes)
                reply(.success(Self.toolText("Arranged \(spokes.count) spoke(s) radially around the hub.")))

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

    /// The map the agent reasons over — nodes + edges as a JSON string. Optionally scoped to one folder.
    @MainActor private static func boardJSON(_ model: AppModel, dir: String?) -> String {
        let scope = dir?.isEmpty == false ? dir : nil
        let nodes: [[String: Any]] = model.board.nodes
            .filter { scope == nil || $0.parentRel == scope! }
            .map { node in
                [
                    "id": node.id.uuidString, "kind": node.kind.rawValue, "name": node.name,
                    "relPath": node.relPath, "parent": node.parentRel,
                    "x": node.x, "y": node.y, "w": node.width, "h": node.height,
                    "expanded": node.isExpanded, "collapsed": node.isCollapsedFolder, "pinned": node.isPinned,
                ]
            }
        let edges: [[String: Any]] = model.board.edges.map { edge in
            [
                "from": edge.from.uuidString, "to": edge.to.uuidString,
                "label": edge.label ?? "", "linkBacked": edge.linkBacked ?? false,
            ]
        }
        let payload: [String: Any] = ["nodes": nodes, "edges": edges]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static let toolSchemas: [[String: Any]] = [
        [
            "name": "canvas_get",
            "description": "Read the canvas: every box (id, kind, name, path, position, size, state) and every connector. Optionally scope to one folder by its relative path.",
            "inputSchema": [
                "type": "object",
                "properties": ["dir": ["type": "string", "description": "Vault-relative folder path to scope to; omit for the whole board."]],
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
            "description": "Lay spokes out radially around a hub box and expand the hub. The app owns placement — you supply intent, not coordinates.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "hubId": ["type": "string", "description": "The box at the center."],
                    "spokeIds": ["type": "array", "items": ["type": "string"], "description": "Boxes to ring around the hub."],
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
