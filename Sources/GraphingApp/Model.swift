import SwiftUI
import AppKit

// MARK: - Geometry helpers

enum Direction {
    case up, down, left, right
}

/// Default size of a new note box. Module-level (nonisolated) so value types like `BoardNode`
/// can use it as the reference size for size-coupled title scaling.
let gappDefaultNoteSize = CGSize(width: 184, height: 74)

/// Source-code file extensions that get a box on the canvas and the code viewer. Module-level
/// (nonisolated) so the `BoardNode` value type can classify its file type without MainActor churn.
let gappCodeExts: Set<String> = [
    "swift", "json", "js", "jsx", "mjs", "cjs", "ts", "tsx", "py", "rb", "go", "rs",
    "java", "kt", "kts", "c", "h", "cpp", "hpp", "cc", "hh", "cs", "sh", "bash", "zsh",
    "fish", "yaml", "yml", "toml", "html", "htm", "css", "scss", "sass", "less", "xml",
    "sql", "php", "lua", "pl", "r", "jl", "m", "mm", "gradle", "ini", "conf", "cfg", "env"
]

/// Extension-less filenames (lowercased) that are still source code.
let gappCodeNames: Set<String> = ["dockerfile", "makefile"]

// MARK: - Board data (the custom save format)

enum NodeKind: String, Codable {
    case note
    case folder
}

/// What a note box's backing file is, derived from its extension. Drives icon + peek renderer.
enum FileType {
    case markdown, csv, code, text
}

/// Named accent palette for boxes. Stored by raw name so the board stays human-readable
/// and forward-compatible. `nil` on a node means "use the app accent".
enum BoxColor: String, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal, graphite

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue:     return Color(red: 0.29, green: 0.56, blue: 0.95)
        case .purple:   return Color(red: 0.58, green: 0.40, blue: 0.93)
        case .pink:     return Color(red: 0.93, green: 0.40, blue: 0.66)
        case .red:      return Color(red: 0.91, green: 0.34, blue: 0.34)
        case .orange:   return Color(red: 0.95, green: 0.58, blue: 0.24)
        case .yellow:   return Color(red: 0.92, green: 0.74, blue: 0.20)
        case .green:    return Color(red: 0.36, green: 0.72, blue: 0.42)
        case .teal:     return Color(red: 0.26, green: 0.71, blue: 0.71)
        case .graphite: return Color(red: 0.48, green: 0.52, blue: 0.57)
        }
    }
}

/// Discrete title text sizes a box can use (multipliers on the base font).
enum TextSize: String, CaseIterable, Identifiable {
    case small, medium, large, xlarge, huge

    var id: String { rawValue }
    var label: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        case .xlarge: return "Extra Large"
        case .huge:   return "Huge"
        }
    }
    var scale: CGFloat {
        switch self {
        case .small:  return 0.85
        case .medium: return 1.0
        case .large:  return 1.3
        case .xlarge: return 1.6
        case .huge:   return 2.0
        }
    }
    /// Nearest discrete size for a stored scale (used to check-mark the active menu item).
    static func from(scale: CGFloat) -> TextSize {
        allCases.min(by: { abs($0.scale - scale) < abs($1.scale - scale) }) ?? .medium
    }
}

/// One box on the canvas. Backed by a real file (.md) or directory on disk.
/// `x`/`y` are the CENTER of the box in world coordinates.
struct BoardNode: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: NodeKind
    var relPath: String          // path relative to the vault root
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    // Optional so older board.json files (without these keys) still decode.
    var colorName: String?       // BoxColor raw value; nil == app accent
    var fontScale: Double?       // title size multiplier; nil == 1.0
    var expanded: Bool?          // note shown as an in-place content card; nil/false == title-only
    var fileId: UInt64?          // disk inode — lets syncFromDisk follow a box to a file's new path

    /// True when this note is showing its content inline as a card.
    var isExpanded: Bool { (expanded ?? false) && kind == .note }

    /// Resolved accent color (named palette entry, or the app accent as fallback).
    var accent: Color {
        if let colorName, let c = BoxColor(rawValue: colorName) { return c.color }
        return Color.accentColor
    }
    /// Title font multiplier (defaults to 1.0).
    var fontScaleValue: CGFloat { CGFloat(fontScale ?? 1.0) }

    /// How much the title scales with the box's own size (notes only): text grows as you resize the
    /// box. 1.0 at the default note size; uses the smaller of the width/height ratios so the text
    /// always fits, clamped to a readable range.
    var sizeScale: CGFloat {
        guard kind == .note else { return 1 }
        let wr = CGFloat(width) / gappDefaultNoteSize.width
        let hr = CGFloat(height) / gappDefaultNoteSize.height
        return min(max(min(wr, hr), 0.5), 6)
    }

    var center: CGPoint {
        get { CGPoint(x: x, y: y) }
        set { x = newValue.x; y = newValue.y }
    }
    var size: CGSize { CGSize(width: width, height: height) }

    /// Box frame in world space (top-left origin).
    var frame: CGRect {
        CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }

    /// File extension (lowercased, no dot), e.g. "md" / "csv". Empty for folders.
    var fileExt: String { (relPath as NSString).pathExtension.lowercased() }

    /// Backing file type, used to pick the icon and the peek renderer.
    var fileType: FileType {
        switch fileExt {
        case "md", "markdown": return .markdown
        case "csv":            return .csv
        default:
            let comp = (relPath as NSString).lastPathComponent.lowercased()
            if gappCodeExts.contains(fileExt) || gappCodeNames.contains(comp) { return .code }
            return .text
        }
    }

    /// Short language label for code files (e.g. "swift", "json"), shown in the code viewer header.
    var codeLanguage: String {
        let comp = (relPath as NSString).lastPathComponent.lowercased()
        if fileExt.isEmpty, gappCodeNames.contains(comp) { return comp }
        return fileExt
    }

    /// Display name: last path component, without the file extension (for notes).
    var name: String {
        let comp = (relPath as NSString).lastPathComponent
        if kind == .note, !fileExt.isEmpty, comp.count > fileExt.count + 1 {
            return String(comp.dropLast(fileExt.count + 1))
        }
        return comp
    }

    /// Parent directory, relative to the vault root ("" == root).
    var parentRel: String {
        (relPath as NSString).deletingLastPathComponent
    }
}

/// Line shape for a connector.
enum EdgeStyle: String, Codable, CaseIterable, Identifiable {
    case curved, straight
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// A visual connection between two boxes (diagram only — not reflected on disk).
/// New style fields are optional so older boards still decode.
struct BoardEdge: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var from: UUID
    var to: UUID
    var colorName: String?   // BoxColor raw value; nil == default secondary
    var directed: Bool?      // nil/true == arrowhead at `to`
    var styleRaw: String?    // EdgeStyle raw value; nil == curved

    var style: EdgeStyle { EdgeStyle(rawValue: styleRaw ?? "") ?? .curved }
    var isDirected: Bool { directed ?? true }
    var color: Color {
        if let colorName, let c = BoxColor(rawValue: colorName) { return c.color }
        return Color.secondary.opacity(0.6)
    }
}

struct BoardData: Codable {
    var nodes: [BoardNode] = []
    var edges: [BoardEdge] = []
    var version: Int = 1
}

// MARK: - Vault (disk + persistence)

/// Wraps a folder on disk (the Obsidian vault). Handles the board sidecar file
/// and all file/folder operations.
struct Vault {
    let root: URL

    private var appDir: URL { root.appendingPathComponent(".graphingapp", isDirectory: true) }
    private var boardURL: URL { appDir.appendingPathComponent("board.json") }

    func url(_ rel: String) -> URL { root.appendingPathComponent(rel) }
    func exists(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: url(rel).path) }

    func ensureAppDir() {
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
    }

    func loadBoard() -> BoardData {
        guard let data = try? Data(contentsOf: boardURL),
              let board = try? JSONDecoder().decode(BoardData.self, from: data) else {
            return BoardData()
        }
        return board
    }

    func saveBoard(_ board: BoardData) {
        ensureAppDir()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try enc.encode(board)
            try data.write(to: boardURL, options: .atomic)
        } catch {
            Log.disk.error("saveBoard failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns a free relative path inside `dir` based on `base`, e.g. "Projects/Untitled 2.md".
    func uniqueRel(dir: String, base: String, ext: String) -> String {
        func make(_ name: String) -> String {
            let comp = ext.isEmpty ? name : "\(name).\(ext)"
            return dir.isEmpty ? comp : "\(dir)/\(comp)"
        }
        if !exists(make(base)) { return make(base) }
        var i = 2
        while exists(make("\(base) \(i)")) { i += 1 }
        return make("\(base) \(i)")
    }

    func relPath(of fileURL: URL) -> String {
        let r = fileURL.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        if r.hasPrefix(base) {
            var s = String(r.dropFirst(base.count))
            if s.hasPrefix("/") { s.removeFirst() }
            return s
        }
        return fileURL.lastPathComponent
    }
}

/// Transient state for a connector being dragged out of a box handle.
/// `toPoint` is in canvas-local screen coordinates.
struct PendingConnect {
    var from: UUID
    var toPoint: CGPoint
    var hoverTarget: UUID?
}

/// One copied/cut box, snapshotted at ⌘C/⌘X time. For a folder, `descendants` holds the
/// boxes living inside it so paste can recreate (copy) or carry (cut) the whole subtree.
struct ClipboardEntry {
    var node: BoardNode
    var descendants: [BoardNode]
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {
    @Published var vault: Vault?
    @Published var board = BoardData()
    @Published var selection: Set<UUID> = []
    @Published var editingId: UUID?
    @Published var selectedEdge: UUID?     // the connector currently selected (if any)
    @Published var pendingConnect: PendingConnect?   // in-progress drag from a handle
    @Published var dropTargetId: UUID?   // folder a dragged box will re-file into (live drop highlight)

    // Clipboard for box copy/cut/paste (internal, disk-aware). See `copyToClipboard` etc.
    @Published private(set) var clipboard: [ClipboardEntry] = []
    @Published private(set) var clipboardIsCut = false
    @Published private(set) var cutIds: Set<UUID> = []   // sources of a pending cut (drawn dimmed)
    private var pasteCount = 0                            // cascade offset for repeated copy-pastes
    var canPaste: Bool { !clipboard.isEmpty }

    @Published var peekId: UUID?     // box whose file content is open in the peek popover (nil == none)

    /// Forced UI appearance. Light when true, dark when false. Persisted; seeded from the
    /// system appearance on first launch so the toggle starts where the user already is.
    @Published var lightTheme: Bool = {
        if let v = UserDefaults.standard.object(forKey: "gapp.lightTheme") as? Bool { return v }
        guard let appearance = NSApp?.effectiveAppearance else { return false }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) != .darkAqua
    }() {
        didSet { UserDefaults.standard.set(lightTheme, forKey: "gapp.lightTheme") }
    }

    // Canvas viewport state
    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero {
        // Pan accumulates from raw scroll deltas with no natural bound. A runaway value (or one
        // derived from an already-corrupt node) would push boxes to ~1e12+ screen coords and pin
        // WindowServer. Clamp to a range that still reaches any in-bounds box at max zoom, but can
        // never reach the meltdown zone. Self-assignment here does not re-fire didSet.
        didSet {
            let c = CGSize(width: AppModel.clampPan(pan.width), height: AppModel.clampPan(pan.height))
            if c != pan { pan = c }
        }
    }
    @Published var viewport: CGSize = .zero
    var canvasFrameGlobal: CGRect = .zero   // CanvasView frame in window space, for the scroll/zoom monitor
    @Published var didInitView = false

    /// Routing lock for a continuous trackpad scroll gesture. When a swipe begins we decide once
    /// whether it pans the canvas or scrolls a card, and keep that decision for the whole gesture —
    /// so panning isn't hijacked when the cursor sweeps across a card mid-swipe. nil == no lock.
    /// Input-only (not @Published — it never affects rendering).
    var scrollOverCard: Bool?

    // MARK: Live file-watching (the read side of the living canvas)

    /// Bumps whenever a watched file's content may have changed (our own write or an external edit in
    /// Obsidian / by an agent). Open content cards & peeks observe this and re-read from disk.
    @Published private(set) var diskRevision = 0
    private var watcher: VaultWatcher?
    /// Vault-relative paths the app itself just wrote, with the time of the write — so the watcher can
    /// tell our own echo from a genuine external change and not loop or re-sync needlessly.
    private var selfWrites: [String: Date] = [:]

    private let defaultsKey = "vaultPath"

    // Default box sizes
    static let noteSize = gappDefaultNoteSize
    static let folderSize = CGSize(width: 340, height: 230)
    static let folderHeaderHeight: CGFloat = 40
    static let folderPadding: CGFloat = 18
    static let folderMinSize = CGSize(width: 200, height: 150)
    static let noteMinSize = CGSize(width: 110, height: 52)
    static let gridStep: CGFloat = 48   // canvas dot-grid spacing; box resize snaps the dragged corner to it

    /// File extensions that get a box on the canvas (besides folders). New files made *in* the app
    /// are still `.md`; other types appear when present on disk (spreadsheets, source code, etc.).
    static let boxableExts: Set<String> = Set(["md", "markdown", "csv"]).union(gappCodeExts)

    /// Default size a note grows to when expanded into an in-place content card.
    static let expandedSize = CGSize(width: 360, height: 320)

    // MARK: Coordinate transforms

    // MARK: World bounds (meltdown guard)

    /// Furthest a box center may sit from the world origin. Generous enough for any realistic
    /// layout, but far below the magnitude (~1e12) where SwiftUI's layout/`.position` math melts
    /// down and pins WindowServer at 100% CPU. Every coordinate written or loaded is clamped here.
    static let worldBound: Double = 1_000_000
    /// Largest pan offset we allow. Reaches any in-bounds box (±`worldBound`) at max zoom (4×) plus
    /// a viewport's worth of slack, yet stays nowhere near the meltdown zone.
    static let panBound: Double = 5_000_000
    /// Box dimensions are clamped to this range — a zero/negative or astronomically large size
    /// also breaks layout.
    static let sizeBound: ClosedRange<Double> = 8 ... 50_000

    static func clampCoord(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(max(v, -worldBound), worldBound)
    }
    static func clampPan(_ v: CGFloat) -> CGFloat {
        guard v.isFinite else { return 0 }
        return min(max(v, -CGFloat(panBound)), CGFloat(panBound))
    }
    static func clampSize(_ v: Double, fallback: Double) -> Double {
        guard v.isFinite, v > 0 else { return fallback }
        return min(max(v, sizeBound.lowerBound), sizeBound.upperBound)
    }

    /// Repair any non-finite / out-of-range geometry already in `board` (e.g. a corrupt board.json
    /// with runaway coordinates). Returns true if anything was changed. A blunt clamp — it may stack
    /// previously-exploded boxes near the world edge, but it guarantees the board can always open
    /// instead of hanging the machine. Run on load; resave when it changes anything.
    @discardableResult
    func sanitizeBoardGeometry() -> Bool {
        var changed = false
        for i in board.nodes.indices {
            let n = board.nodes[i]
            let nx = AppModel.clampCoord(n.x)
            let ny = AppModel.clampCoord(n.y)
            let nw = AppModel.clampSize(n.width, fallback: gappDefaultNoteSize.width)
            let nh = AppModel.clampSize(n.height, fallback: gappDefaultNoteSize.height)
            if nx != n.x || ny != n.y || nw != n.width || nh != n.height {
                board.nodes[i].x = nx; board.nodes[i].y = ny
                board.nodes[i].width = nw; board.nodes[i].height = nh
                changed = true
            }
        }
        if changed {
            Log.disk.fault("Sanitized out-of-range board geometry on load (clamped to ±\(Int(AppModel.worldBound), privacy: .public)) — board.json had runaway coordinates.")
        }
        return changed
    }

    /// A folder bigger than this isn't a layout, it's corruption (one child stranded far from its
    /// siblings makes the folder auto-grow without bound and become unclickable).
    static let maxSaneFolderSpan: CGFloat = 20000
    /// A child this far from its siblings' median is stranded and gets pulled back in.
    static let strandRadius: CGFloat = 12000

    /// Repair corrupt layouts where a folder child sits absurdly far from its siblings (e.g. a leftover
    /// from the S10 coordinate repair), which makes the folder's `effectiveFrame` balloon to an
    /// unclickable size. Deepest folders first, so an inner fix settles before its parent is measured.
    /// Conservative: only egregious outliers move (carrying their own subtree), and a folder's stored
    /// frame is reset only when it was bloated past sanity — normal layouts are left untouched. Runs at
    /// load (not undoable). Returns true if anything changed.
    @discardableResult
    func reinInStrandedChildren() -> Bool {
        var changed = false
        let deepestFirst = board.nodes
            .filter { $0.kind == .folder }
            .sorted { $0.relPath.filter { $0 == "/" }.count > $1.relPath.filter { $0 == "/" }.count }
        for folder in deepestFirst {
            guard let fi = board.nodes.firstIndex(where: { $0.id == folder.id }) else { continue }
            let kids = directChildren(of: folder.relPath)
            guard !kids.isEmpty else { continue }
            let frame = effectiveFrame(of: folder)
            guard frame.width > AppModel.maxSaneFolderSpan || frame.height > AppModel.maxSaneFolderSpan else { continue }

            let anchorX = median(kids.map { $0.center.x })
            let anchorY = median(kids.map { $0.center.y })
            var slot = 0
            for kid in kids where hypot(kid.center.x - anchorX, kid.center.y - anchorY) > AppModel.strandRadius {
                moveSubtree(kid.id, to: CGPoint(x: anchorX + CGFloat(slot % 4) * 180 - 270,
                                                y: anchorY + CGFloat(slot / 4) * 110 + 70))
                slot += 1
            }
            if board.nodes[fi].width > AppModel.maxSaneFolderSpan || board.nodes[fi].height > AppModel.maxSaneFolderSpan {
                board.nodes[fi].width = AppModel.folderSize.width
                board.nodes[fi].height = AppModel.folderSize.height
            }
            board.nodes[fi].center = CGPoint(x: anchorX, y: anchorY)
            changed = true
        }
        if changed {
            Log.canvas.notice("Reined in stranded folder children on load — a box was far enough from its siblings to balloon its folder.")
        }
        return changed
    }

    /// Move a box (and its whole subtree, rigid-body) so the box lands at `center`. Coordinates clamped.
    private func moveSubtree(_ id: UUID, to center: CGPoint) {
        guard let i = board.nodes.firstIndex(where: { $0.id == id }) else { return }
        let dx = center.x - board.nodes[i].center.x
        let dy = center.y - board.nodes[i].center.y
        board.nodes[i].center = CGPoint(x: AppModel.clampCoord(center.x), y: AppModel.clampCoord(center.y))
        let prefix = board.nodes[i].relPath + "/"
        for j in board.nodes.indices where board.nodes[j].relPath.hasPrefix(prefix) {
            board.nodes[j].center = CGPoint(x: AppModel.clampCoord(board.nodes[j].center.x + dx),
                                            y: AppModel.clampCoord(board.nodes[j].center.y + dy))
        }
    }

    private func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    func worldToScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * zoom + pan.width, y: p.y * zoom + pan.height)
    }

    func screenToWorld(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - pan.width) / zoom, y: (p.y - pan.height) / zoom)
    }

    /// Convert a point in global (window) space to canvas-local screen space by removing the canvas
    /// frame's origin — the step before `screenToWorld` for any gesture using `.global` coordinates.
    /// Shared by the canvas background and the per-node drag/connect gestures.
    func canvasLocal(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - canvasFrameGlobal.minX,
                y: global.y - canvasFrameGlobal.minY)
    }

    /// Convert a `.global`-space gesture location to a world point: subtract the canvas's window
    /// origin, then undo pan/zoom. (Mirrors the `canvasLocal` + `screenToWorld` pair at the handles.)
    func worldFromGlobal(_ global: CGPoint) -> CGPoint {
        screenToWorld(CGPoint(x: global.x - canvasFrameGlobal.minX,
                              y: global.y - canvasFrameGlobal.minY))
    }

    /// Zoom while keeping the world point under `screenPoint` fixed (cursor-anchored zoom).
    func zoomToward(_ screenPoint: CGPoint, factor: CGFloat) {
        let newZoom = max(0.2, min(4, zoom * factor))
        guard abs(newZoom - zoom) > .ulpOfOne else { return }
        let w = screenToWorld(screenPoint)
        zoom = newZoom
        pan = CGSize(width: screenPoint.x - w.x * newZoom,
                     height: screenPoint.y - w.y * newZoom)
    }

    // MARK: Vault lifecycle

    func restoreLastVault() {
        guard let path = UserDefaults.standard.string(forKey: defaultsKey) else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            openVault(at: url)
        }
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Vault"
        panel.message = "Pick the folder (Obsidian vault) where notes and folders will live."
        if panel.runModal() == .OK, let url = panel.url {
            openVault(at: url)
        }
    }

    func openVault(at url: URL) {
        let v = Vault(root: url)
        vault = v
        board = v.loadBoard()
        // Self-heal a corrupt board before it can hang or become unusable: clamp runaway coords, then
        // pull any stranded folder child back so no folder auto-grows to an unclickable size.
        let repaired = sanitizeBoardGeometry()
        let healed = reinInStrandedChildren()
        if repaired || healed { v.saveBoard(board) }
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
        clearHistory()
        syncFromDisk()
        didInitView = false
        startWatching()
    }

    func closeVault() {
        stopWatching()
        vault = nil
        board = BoardData()
        selection = []
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// Begin (or restart) watching the open vault for external file changes.
    private func startWatching() {
        watcher = nil   // releasing the old watcher stops its stream (deinit)
        guard let vault else { return }
        watcher = VaultWatcher(root: vault.root) { [weak self] rels in
            Task { @MainActor in self?.handleDiskChange(rels) }
        }
        Log.disk.notice("watching vault for external changes: \(vault.root.path, privacy: .public)")
    }

    private func stopWatching() { watcher = nil }

    /// Record that the app itself just wrote `rel`, so the watcher's echo of that write is recognized
    /// as ours (not an external edit). Called from every raw disk op.
    private func markSelfWrite(_ rel: String) {
        guard !rel.isEmpty else { return }
        selfWrites[rel] = Date()
    }

    /// True if the app wrote `rel` within the suppression window (covers FSEvents latency + debounce).
    private func isRecentSelfWrite(_ rel: String) -> Bool {
        guard let when = selfWrites[rel] else { return false }
        return Date().timeIntervalSince(when) < 2
    }

    /// React to a debounced batch of changed vault-relative paths from the watcher.
    func handleDiskChange(_ rels: [String]) {
        guard vault != nil else { return }
        let relevant = rels.filter { !$0.hasPrefix(".graphingapp") }   // our own board.json isn't content
        guard !relevant.isEmpty else { return }
        // Any content change (ours or external) → open cards/peeks re-read. The views guard against
        // clobbering an in-progress edit; re-reading after our own link-write is what makes a drawn
        // connector's `[[link]]` appear live in the source note's card.
        diskRevision &+= 1
        // Reconcile structure (new/deleted/moved boxes) only for EXTERNAL changes — our own
        // create/move/trash already updated the board in its transaction — and never mid-interaction,
        // so a drag/resize isn't yanked out from under the user.
        let hasExternal = relevant.contains { !isRecentSelfWrite($0) }
        if hasExternal, interactionBefore == nil { syncFromDisk() }
    }

    var vaultName: String { vault?.root.lastPathComponent ?? "No Vault" }

    // MARK: Disk <-> board sync

    /// Reconcile the board with what is actually on disk: drop boxes whose file
    /// vanished, and add boxes for files/folders created elsewhere (e.g. Obsidian).
    func syncFromDisk() {
        guard let vault else { return }
        let fm = FileManager.default

        var diskRels = Set<String>()
        var dirRels = Set<String>()
        var relByInode: [UInt64: String] = [:]   // disk inode -> its current path, for move detection
        var inodeByRel: [String: UInt64] = [:]
        if let en = fm.enumerator(at: vault.root,
                                  includingPropertiesForKeys: [.isDirectoryKey],
                                  options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in en {
                let rel = vault.relPath(of: fileURL)
                if rel.hasPrefix(".graphingapp") || rel.isEmpty { continue }
                let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir {
                    diskRels.insert(rel)
                    dirRels.insert(rel)
                } else if AppModel.boxableExts.contains(fileURL.pathExtension.lowercased()) {
                    diskRels.insert(rel)
                } else {
                    continue
                }
                if let ino = AppModel.inode(of: fileURL) { relByInode[ino] = rel; inodeByRel[rel] = ino }
            }
        }

        // Follow moves/renames: a box whose path vanished but whose stored inode now lives at a new
        // path didn't disappear — it MOVED (a rename in Obsidian/Finder). Repoint it and keep its
        // position, instead of dropping it and re-adding a stranger. This is what stops an external
        // folder rename from collapsing its whole subtree onto a default corner.
        for i in board.nodes.indices {
            let node = board.nodes[i]
            guard !diskRels.contains(node.relPath), let ino = node.fileId, let moved = relByInode[ino],
                  !board.nodes.contains(where: { $0.relPath == moved }) else { continue }
            board.nodes[i].relPath = moved
        }

        // Drop boxes whose backing file is genuinely gone.
        board.nodes.removeAll { !diskRels.contains($0.relPath) }
        let known = Set(board.nodes.map { $0.relPath })

        // Add boxes for genuinely-new files, tucked near their parent folder — never a fixed far
        // corner, which used to strand them and balloon the folder's auto-grown frame.
        for (index, rel) in diskRels.subtracting(known).sorted().enumerated() {
            let isDir = dirRels.contains(rel)
            let size = isDir ? AppModel.folderSize : AppModel.noteSize
            let center = spawnCenter(forNew: rel, index: index)
            var node = BoardNode(kind: isDir ? .folder : .note, relPath: rel,
                                 x: center.x, y: center.y, width: size.width, height: size.height)
            node.fileId = inodeByRel[rel]
            board.nodes.append(node)
        }

        // Refresh inodes so the next sync can detect moves (also backfills boxes from an older board).
        for i in board.nodes.indices {
            if let ino = inodeByRel[board.nodes[i].relPath] { board.nodes[i].fileId = ino }
        }

        // Clean up dangling edges.
        let ids = Set(board.nodes.map { $0.id })
        board.edges.removeAll { !ids.contains($0.from) || !ids.contains($0.to) }
        save()
    }

    /// The file's inode — stable across renames/moves on the same volume, so `syncFromDisk` can follow
    /// a box to a file's new path instead of dropping it.
    static func inode(of url: URL) -> UInt64? {
        guard let number = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber]
        else { return nil }
        return (number as? NSNumber)?.uint64Value
    }

    /// Where to place a box newly discovered on disk: next to its parent folder's existing children
    /// (or the folder box itself), else near the viewport the user is looking at — with a small
    /// cascade for batches. Never a fixed far corner (which stranded children and ballooned folders).
    private func spawnCenter(forNew rel: String, index: Int) -> CGPoint {
        let parent = (rel as NSString).deletingLastPathComponent
        let anchor: CGPoint
        if !parent.isEmpty,
           let near = directChildren(of: parent).first?.center
                      ?? board.nodes.first(where: { $0.relPath == parent })?.center {
            anchor = CGPoint(x: near.x + 150, y: near.y)
        } else if viewport != .zero {
            anchor = screenToWorld(CGPoint(x: viewport.width / 2, y: viewport.height / 2))
        } else {
            anchor = CGPoint(x: 10000, y: 10000)
        }
        return CGPoint(x: anchor.x + CGFloat(index % 5) * 200, y: anchor.y + CGFloat(index / 5) * 120)
    }

    // MARK: Lookups

    func node(_ id: UUID) -> BoardNode? { board.nodes.first { $0.id == id } }

    /// Topmost (smallest, most specific) box whose displayed frame contains a world point.
    func node(atWorld point: CGPoint) -> BoardNode? {
        smallestBox(containing: point)
    }

    /// The folder box (if any) whose displayed frame contains the given world point.
    func folderNode(containing point: CGPoint, excluding excludeId: UUID? = nil) -> BoardNode? {
        smallestBox(containing: point) { $0.kind == .folder && $0.id != excludeId }
    }

    /// Smallest-area box whose displayed frame contains `point` — the topmost, most specific hit —
    /// optionally limited to boxes passing `include`. One pass that keeps the running minimum and
    /// computes each `effectiveFrame` only for candidates: no full sort, no intermediate arrays.
    private func smallestBox(containing point: CGPoint,
                             where include: (BoardNode) -> Bool = { _ in true }) -> BoardNode? {
        board.nodes
            .compactMap { node -> (node: BoardNode, area: CGFloat)? in
                guard include(node) else { return nil }
                let frame = effectiveFrame(of: node)
                guard frame.contains(point) else { return nil }
                return (node, frame.width * frame.height)
            }
            .min { $0.area < $1.area }?.node
    }

    /// Folder under `point` that box `id` could legally re-file into: the smallest folder
    /// containing the point, never the box itself or — for a dragged folder — one of its own
    /// descendants (a folder can't be dropped inside itself). nil → no such folder (drop → root).
    func reFileFolder(under point: CGPoint, for id: UUID) -> BoardNode? {
        guard let dragged = node(id),
              let folder = folderNode(containing: point, excluding: id),
              !(dragged.kind == .folder && (folder.relPath == dragged.relPath
                                            || folder.relPath.hasPrefix(dragged.relPath + "/")))
        else { return nil }
        return folder
    }

    /// Folder to highlight live while dragging box `id` over `point` — the re-file target, but
    /// nil when the box is already in it, so we don't flash its current parent on every jiggle.
    func dropTargetHighlight(for id: UUID, at point: CGPoint) -> UUID? {
        guard let folder = reFileFolder(under: point, for: id),
              folder.relPath != node(id)?.parentRel else { return nil }
        return folder.id
    }

    /// Nearest center to `desired` where box `id`'s hitbox (its `effectiveFrame`) clears all of its
    /// SIBLINGS' hitboxes — same-parent boxes only, since a folder must still contain its own
    /// children. Returns `desired` when it's already free, or nil if nothing's free within the capped
    /// spiral (caller then accepts the overlap). A folder's whole subtree translates together, so its
    /// hitbox just shifts by the candidate delta — hence the offset probe.
    func nearestFreeCenter(for id: UUID, near desired: CGPoint) -> CGPoint? {
        guard let box = node(id) else { return nil }
        let hitbox = effectiveFrame(of: box)
        let siblings = board.nodes
            .filter { $0.parentRel == box.parentRel && $0.id != id }
            .map { effectiveFrame(of: $0) }
        func isFree(_ c: CGPoint) -> Bool {
            let probe = hitbox.offsetBy(dx: c.x - box.center.x, dy: c.y - box.center.y)
            return !siblings.contains { $0.intersects(probe) }
        }
        if isFree(desired) { return desired }
        let step = AppModel.gridStep
        // ponytail: capped ring scan on the grid; if no gap within ~24 rings, accept the overlap.
        for ring in 1...24 {
            let r = CGFloat(ring) * step
            for k in -ring...ring {
                let o = CGFloat(k) * step
                for c in [CGPoint(x: desired.x + o, y: desired.y - r),
                          CGPoint(x: desired.x + o, y: desired.y + r),
                          CGPoint(x: desired.x - r, y: desired.y + o),
                          CGPoint(x: desired.x + r, y: desired.y + o)] where isFree(c) {
                    return c
                }
            }
        }
        return nil
    }

    /// Boxes whose parent folder is exactly `relPath` (one level down).
    func directChildren(of relPath: String) -> [BoardNode] {
        board.nodes.filter { $0.parentRel == relPath }
    }

    /// A folder's displayed frame: its stored frame, grown to enclose its contents
    /// (plus padding and header). Notes return their plain frame.
    ///
    /// This runs on **every render** and recurses through nested folders. If the board ever
    /// holds a cycle (a folder that is its own ancestor, e.g. a corrupt `board.json` or a
    /// duplicate relPath from a sync glitch), naive recursion spins the CPU forever and pins
    /// WindowServer — exactly the meltdown we're guarding against. The visited-set + depth cap
    /// turn that into a bounded, logged no-op instead of a hang.
    func effectiveFrame(of node: BoardNode) -> CGRect {
        var visited = Set<String>()
        return effectiveFrame(of: node, visited: &visited, depth: 0)
    }

    /// Max nesting we'll ever walk before assuming the graph is pathological.
    private static let maxFolderDepth = 256
    private var lastFolderCycleWarning: Date?

    private func effectiveFrame(of node: BoardNode, visited: inout Set<String>, depth: Int) -> CGRect {
        guard node.kind == .folder else { return node.frame }
        // Cycle / runaway guard: bail loudly rather than recurse into an infinite loop.
        guard depth < AppModel.maxFolderDepth, visited.insert(node.relPath).inserted else {
            warnFolderCycle(at: node.relPath, depth: depth)
            return node.frame
        }
        var frame = node.frame
        let children = directChildren(of: node.relPath)
        if !children.isEmpty {
            var bounds = effectiveFrame(of: children[0], visited: &visited, depth: depth + 1)
            for child in children.dropFirst() {
                bounds = bounds.union(effectiveFrame(of: child, visited: &visited, depth: depth + 1))
            }
            let pad = AppModel.folderPadding
            let needed = CGRect(x: bounds.minX - pad,
                                y: bounds.minY - pad - AppModel.folderHeaderHeight,
                                width: bounds.width + 2 * pad,
                                height: bounds.height + 2 * pad + AppModel.folderHeaderHeight)
            frame = frame.union(needed)
        }
        return frame
    }

    /// The rectangle a folder must cover to enclose its direct contents (children's displayed
    /// bounds + padding + header), or nil when empty. Same region `effectiveFrame` auto-grows into;
    /// the resize clamp uses it so a folder can't be drawn smaller than what it holds.
    func contentsBounds(of node: BoardNode) -> CGRect? {
        let children = directChildren(of: node.relPath)
        guard let first = children.first else { return nil }
        var bounds = effectiveFrame(of: first)
        for child in children.dropFirst() { bounds = bounds.union(effectiveFrame(of: child)) }
        let pad = AppModel.folderPadding
        return CGRect(x: bounds.minX - pad,
                      y: bounds.minY - pad - AppModel.folderHeaderHeight,
                      width: bounds.width + 2 * pad,
                      height: bounds.height + 2 * pad + AppModel.folderHeaderHeight)
    }

    /// Log a folder-graph cycle at most once every 5s (this path can fire every frame).
    private func warnFolderCycle(at relPath: String, depth: Int) {
        let now = Date()
        if let last = lastFolderCycleWarning, now.timeIntervalSince(last) < 5 { return }
        lastFolderCycleWarning = now
        Log.canvas.fault("Folder layout cycle/overflow at \(relPath, privacy: .public) (depth \(depth)) — bailing to avoid a redraw loop. board.json may be corrupt.")
    }

    // MARK: Mutations

    func save() {
        vault?.saveBoard(board)
    }

    // MARK: Undo / redo

    private struct UndoStep { let undo: () -> Void; let redo: () -> Void }
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private var undoStack: [UndoStep] = []
    private var redoStack: [UndoStep] = []
    private let maxUndo = 200

    // transaction state (supports nesting so spawn = one step)
    private var txnDepth = 0
    private var txnBefore: BoardData?
    private var txnFileUndo: [() -> Void] = []
    private var txnFileRedo: [() -> Void] = []
    // drag/resize snapshot
    private var interactionBefore: BoardData?

    private func recordStep(undo: @escaping () -> Void, redo: @escaping () -> Void) {
        undoStack.append(UndoStep(undo: undo, redo: redo))
        if undoStack.count > maxUndo { undoStack.removeFirst() }
        redoStack.removeAll()
        canUndo = true
        canRedo = false
    }

    func performUndo() {
        guard let step = undoStack.popLast() else { return }
        editingId = nil
        step.undo()
        redoStack.append(step)
        canUndo = !undoStack.isEmpty
        canRedo = true
        pruneSelection()
    }

    func performRedo() {
        guard let step = redoStack.popLast() else { return }
        editingId = nil
        step.redo()
        undoStack.append(step)
        canUndo = true
        canRedo = !redoStack.isEmpty
        pruneSelection()
    }

    func clearHistory() {
        undoStack.removeAll(); redoStack.removeAll()
        canUndo = false; canRedo = false
    }

    private func pruneSelection() {
        selection = selection.intersection(Set(board.nodes.map { $0.id }))
        if let e = selectedEdge, !board.edges.contains(where: { $0.id == e }) { selectedEdge = nil }
        if let p = peekId, !board.nodes.contains(where: { $0.id == p }) { peekId = nil }
    }

    /// Run a mutating action as a single undoable transaction (nestable).
    private func transaction(_ body: () -> Void) {
        if txnDepth == 0 { txnBefore = board; txnFileUndo = []; txnFileRedo = [] }
        txnDepth += 1
        body()
        txnDepth -= 1
        if txnDepth == 0, let before = txnBefore {
            txnBefore = nil
            commit(before: before, fileUndo: txnFileUndo, fileRedo: txnFileRedo)
            txnFileUndo = []; txnFileRedo = []
        }
    }

    private func commit(before: BoardData, fileUndo: [() -> Void], fileRedo: [() -> Void]) {
        let after = board
        if before.nodes == after.nodes && before.edges == after.edges && fileUndo.isEmpty { return }
        recordStep(
            undo: { fileUndo.reversed().forEach { $0() }; self.board = before; self.save() },
            redo: { fileRedo.forEach { $0() }; self.board = after; self.save() }
        )
        save()
    }

    // Raw disk ops (not recorded). Each marks the paths it touches as a self-write so the file
    // watcher doesn't mistake the app's own change for an external edit.
    private func rawCreateFile(_ rel: String) {
        guard let vault else { return }
        markSelfWrite(rel)
        FileManager.default.createFile(atPath: vault.url(rel).path, contents: Data())
    }
    private func rawCreateDir(_ rel: String) {
        guard let vault, !rel.isEmpty else { return }
        markSelfWrite(rel)
        try? FileManager.default.createDirectory(at: vault.url(rel), withIntermediateDirectories: true)
    }
    private func rawMove(_ from: String, _ to: String) {
        guard let vault else { return }
        markSelfWrite(from); markSelfWrite(to)
        let parent = (to as NSString).deletingLastPathComponent
        if !parent.isEmpty {
            try? FileManager.default.createDirectory(at: vault.url(parent), withIntermediateDirectories: true)
        }
        try? FileManager.default.moveItem(at: vault.url(from), to: vault.url(to))
    }
    private func rawTrash(_ rel: String) -> URL? {
        guard let vault else { return nil }
        markSelfWrite(rel)
        var out: NSURL?
        try? FileManager.default.trashItem(at: vault.url(rel), resultingItemURL: &out)
        return out as URL?
    }
    private func rawRestore(_ trashURL: URL, to rel: String) {
        guard let vault else { return }
        markSelfWrite(rel)
        let parent = (rel as NSString).deletingLastPathComponent
        if !parent.isEmpty {
            try? FileManager.default.createDirectory(at: vault.url(parent), withIntermediateDirectories: true)
        }
        try? FileManager.default.moveItem(at: trashURL, to: vault.url(rel))
    }

    // Recorded disk ops (must run inside a transaction)
    private func tCreateFile(_ rel: String) {
        rawCreateFile(rel)
        txnFileRedo.append { self.rawCreateFile(rel) }
        txnFileUndo.append { _ = self.rawTrash(rel) }
    }
    private func tCreateDir(_ rel: String) {
        rawCreateDir(rel)
        txnFileRedo.append { self.rawCreateDir(rel) }
        txnFileUndo.append { _ = self.rawTrash(rel) }
    }
    private func tMove(_ from: String, _ to: String) {
        rawMove(from, to)
        txnFileRedo.append { self.rawMove(from, to) }
        txnFileUndo.append { self.rawMove(to, from) }
    }
    private func rawCopy(_ from: String, _ to: String) {
        guard let vault else { return }
        markSelfWrite(to)
        let parent = (to as NSString).deletingLastPathComponent
        if !parent.isEmpty {
            try? FileManager.default.createDirectory(at: vault.url(parent), withIntermediateDirectories: true)
        }
        // copyItem recurses for directories, so a folder's whole subtree is duplicated.
        try? FileManager.default.copyItem(at: vault.url(from), to: vault.url(to))
    }
    private func tCopy(_ from: String, _ to: String) {
        rawCopy(from, to)
        txnFileRedo.append { self.rawCopy(from, to) }
        txnFileUndo.append { _ = self.rawTrash(to) }
    }
    private func tTrash(_ rel: String) {
        var url = rawTrash(rel)
        txnFileRedo.append { url = self.rawTrash(rel) }
        txnFileUndo.append { if let u = url { self.rawRestore(u, to: rel) } }
    }

    // MARK: Drag / resize interaction

    func beginInteraction() {
        if interactionBefore == nil { interactionBefore = board }
    }

    /// End a resize or pure reposition (board-only change).
    func endInteraction() {
        guard let before = interactionBefore else { return }
        interactionBefore = nil
        commit(before: before, fileUndo: [], fileRedo: [])
    }

    /// End a node drag: re-file into a folder if dropped inside one. Records the
    /// reposition AND any disk move as a single undo step.
    func endDrag(_ id: UUID, at dropPoint: CGPoint) {
        dropTargetId = nil
        guard let before = interactionBefore,
              let current = node(id),
              let idx = board.nodes.firstIndex(where: { $0.id == id }) else {
            interactionBefore = nil
            return
        }
        interactionBefore = nil
        var fU: [() -> Void] = []
        var fR: [() -> Void] = []

        func relocate(to newDir: String) {
            let name = (current.relPath as NSString).lastPathComponent
            let newRel = newDir.isEmpty ? name : "\(newDir)/\(name)"
            guard newRel != current.relPath else { return }
            guard vault?.exists(newRel) == false else {
                NSSound.beep()   // a file with this name already lives in the target — keep it put
                return
            }
            let oldRel = current.relPath
            Log.disk.notice("re-file on drop: \(oldRel, privacy: .public) -> \(newRel, privacy: .public)")
            rawMove(oldRel, newRel)
            fR.append { self.rawMove(oldRel, newRel) }
            fU.append { self.rawMove(newRel, oldRel) }
            board.nodes[idx].relPath = newRel
            if current.kind == .folder { reparentChildren(oldPrefix: oldRel, newPrefix: newRel) }
        }

        // Re-file by where the cursor dropped, not the box center — so a box can land in a small
        // nested folder even when the box's own center never reaches it.
        if let folder = reFileFolder(under: dropPoint, for: id) {
            if folder.relPath != current.parentRel { relocate(to: folder.relPath) }
        } else if current.parentRel != "" {
            relocate(to: "")
        }

        // Settle on drop: if the box landed overlapping a sibling, slide it (and, for a folder, its
        // whole subtree) to the nearest free spot. Runs after any re-file so siblings are measured in
        // the box's final folder; the nudge rides this drag's single undo step. Only new drops settle
        // — existing overlaps on load are left untouched.
        let landed = board.nodes[idx].center
        if let free = nearestFreeCenter(for: id, near: landed), free != landed {
            let dx = free.x - landed.x, dy = free.y - landed.y
            board.nodes[idx].center = CGPoint(x: AppModel.clampCoord(free.x), y: AppModel.clampCoord(free.y))
            if current.kind == .folder {
                let prefix = board.nodes[idx].relPath + "/"
                for di in board.nodes.indices where board.nodes[di].relPath.hasPrefix(prefix) {
                    board.nodes[di].center = CGPoint(x: AppModel.clampCoord(board.nodes[di].center.x + dx),
                                                     y: AppModel.clampCoord(board.nodes[di].center.y + dy))
                }
            }
        }

        commit(before: before, fileUndo: fU, fileRedo: fR)
    }

    @discardableResult
    func addNote(inDir dir: String, at center: CGPoint, beginEditing: Bool = true) -> UUID? {
        guard let vault else { return nil }
        var newId: UUID?
        transaction {
            if !dir.isEmpty { rawCreateDir(dir) }
            let rel = vault.uniqueRel(dir: dir, base: "Untitled", ext: "md")
            tCreateFile(rel)
            let node = BoardNode(kind: .note, relPath: rel,
                                 x: center.x, y: center.y,
                                 width: AppModel.noteSize.width, height: AppModel.noteSize.height)
            board.nodes.append(node)
            selection = [node.id]
            selectedEdge = nil
            if beginEditing { editingId = node.id }
            newId = node.id
        }
        return newId
    }

    @discardableResult
    func addFolder(inDir dir: String, at center: CGPoint, beginEditing: Bool = true) -> UUID? {
        guard let vault else { return nil }
        var newId: UUID?
        transaction {
            if !dir.isEmpty { rawCreateDir(dir) }
            let rel = vault.uniqueRel(dir: dir, base: "Folder", ext: "")
            tCreateDir(rel)
            let node = BoardNode(kind: .folder, relPath: rel,
                                 x: center.x, y: center.y,
                                 width: AppModel.folderSize.width, height: AppModel.folderSize.height)
            board.nodes.append(node)
            selection = [node.id]
            selectedEdge = nil
            if beginEditing { editingId = node.id }
            newId = node.id
        }
        return newId
    }

    /// The Miro move: spawn a connected SIBLING of the same kind, beside the box.
    func spawn(from node: BoardNode, direction: Direction) {
        let gap: CGFloat = 56
        let newSize = node.kind == .folder ? AppModel.folderSize : AppModel.noteSize
        var c = node.center
        switch direction {
        case .right: c.x += node.size.width / 2 + gap + newSize.width / 2
        case .left:  c.x -= node.size.width / 2 + gap + newSize.width / 2
        case .down:  c.y += node.size.height / 2 + gap + newSize.height / 2
        case .up:    c.y -= node.size.height / 2 + gap + newSize.height / 2
        }
        // Sibling: same parent folder as the source box.
        let dir = node.parentRel
        transaction {
            let newId = node.kind == .folder ? addFolder(inDir: dir, at: c) : addNote(inDir: dir, at: c)
            if let newId {
                board.edges.append(BoardEdge(from: node.id, to: newId))
                if let sibling = self.node(newId) { writeLink(from: node, to: sibling) }
            }
        }
    }

    /// Add a note inside a folder (used by the folder header "+" button).
    @discardableResult
    func addChildNote(inFolder folder: BoardNode) -> UUID? {
        let count = board.nodes.filter { $0.parentRel == folder.relPath }.count
        let x = folder.x - folder.width / 2 + 56 + CGFloat(count % 3) * 150
        let y = folder.y - folder.height / 2 + 70 + CGFloat(count / 3) * 84
        return addNote(inDir: folder.relPath, at: CGPoint(x: x, y: y))
    }

    func rename(_ id: UUID, to newName: String) {
        guard let vault, let idx = board.nodes.firstIndex(where: { $0.id == id }) else { return }
        let node = board.nodes[idx]
        let safe = newName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !safe.isEmpty, safe != node.name else { return }

        let dir = node.parentRel
        let ext = node.fileExt   // preserves .md / .csv / etc.; "" for folders
        let comp = ext.isEmpty ? safe : "\(safe).\(ext)"
        let newRel = dir.isEmpty ? comp : "\(dir)/\(comp)"
        guard !vault.exists(newRel) else { NSSound.beep(); return }
        let oldRel = node.relPath

        transaction {
            tMove(oldRel, newRel)
            board.nodes[idx].relPath = newRel
            if node.kind == .folder {
                reparentChildren(oldPrefix: oldRel, newPrefix: newRel)
            }
        }
    }

    /// Move a box into a folder (or to root when `newDir` == ""). Mirrors the move on disk.
    func move(_ id: UUID, intoDir newDir: String) {
        guard let vault, let idx = board.nodes.firstIndex(where: { $0.id == id }) else { return }
        let node = board.nodes[idx]
        guard node.parentRel != newDir else { return }
        // Don't move a folder into itself or a descendant.
        if node.kind == .folder, newDir == node.relPath || newDir.hasPrefix(node.relPath + "/") { return }

        let name = (node.relPath as NSString).lastPathComponent
        let newRel = newDir.isEmpty ? name : "\(newDir)/\(name)"
        guard !vault.exists(newRel) else { NSSound.beep(); return }
        let oldRel = node.relPath

        transaction {
            tMove(oldRel, newRel)
            board.nodes[idx].relPath = newRel
            if node.kind == .folder {
                reparentChildren(oldPrefix: oldRel, newPrefix: newRel)
            }
        }
    }

    private func reparentChildren(oldPrefix: String, newPrefix: String) {
        for i in board.nodes.indices where board.nodes[i].relPath.hasPrefix(oldPrefix + "/") {
            board.nodes[i].relPath = newPrefix + String(board.nodes[i].relPath.dropFirst(oldPrefix.count))
        }
    }

    func delete(_ ids: Set<UUID>) {
        guard vault != nil else { return }
        let targets = board.nodes.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        Log.disk.notice("delete \(targets.count) box(es): \(targets.map(\.relPath).joined(separator: ", "), privacy: .public)")

        // Also remove descendants of any deleted folder (their files go with the folder).
        var removeIds = ids
        for n in targets where n.kind == .folder {
            for m in board.nodes where m.relPath.hasPrefix(n.relPath + "/") {
                removeIds.insert(m.id)
            }
        }

        transaction {
            for n in targets { tTrash(n.relPath) }
            board.nodes.removeAll { removeIds.contains($0.id) }
            board.edges.removeAll { removeIds.contains($0.from) || removeIds.contains($0.to) }
            selection.subtract(removeIds)
            if let editingId, removeIds.contains(editingId) { self.editingId = nil }
        }
    }

    // MARK: Clipboard (copy / cut / paste)

    /// Snapshot a selection into clipboard entries: keep only the top-level boxes (drop any whose
    /// ancestor folder is also selected) and attach each folder's descendant boxes.
    private func clipboardEntries(from ids: Set<UUID>) -> [ClipboardEntry] {
        let chosen = board.nodes.filter { ids.contains($0.id) }
        let chosenFolders = chosen.filter { $0.kind == .folder }.map { $0.relPath }
        let roots = chosen.filter { n in
            !chosenFolders.contains { anc in n.relPath != anc && n.relPath.hasPrefix(anc + "/") }
        }
        return roots.map { root in
            let desc = root.kind == .folder
                ? board.nodes.filter { $0.relPath.hasPrefix(root.relPath + "/") }
                : []
            return ClipboardEntry(node: root, descendants: desc)
        }
    }

    func copyToClipboard() {
        let entries = clipboardEntries(from: selection)
        guard !entries.isEmpty else { return }
        clipboard = entries
        clipboardIsCut = false
        cutIds = []
        pasteCount = 0
    }

    func cutToClipboard() {
        let entries = clipboardEntries(from: selection)
        guard !entries.isEmpty else { return }
        clipboard = entries
        clipboardIsCut = true
        cutIds = Set(entries.flatMap { [$0.node.id] + $0.descendants.map(\.id) })
        pasteCount = 0
    }

    /// Paste the clipboard near `point`, filing into the folder under it (or the root). Copy
    /// duplicates files on disk ("… copy"); cut moves the originals. One undoable transaction.
    func paste(at point: CGPoint) {
        guard let vault, !clipboard.isEmpty else { return }
        let isCut = clipboardIsCut

        // File into the folder under the paste point — but never nest a pasted folder in itself.
        var targetDir = folderNode(containing: point)?.relPath ?? ""
        let rootPaths = clipboard.map { $0.node.relPath }
        if rootPaths.contains(where: { targetDir == $0 || targetDir.hasPrefix($0 + "/") }) {
            targetDir = ""
        }

        // Move the whole group so the centroid of its roots lands on the paste point.
        let centers = clipboard.map { $0.node.center }
        let anchor = CGPoint(x: centers.map(\.x).reduce(0, +) / Double(centers.count),
                             y: centers.map(\.y).reduce(0, +) / Double(centers.count))
        let cascade = isCut ? 0 : Double(pasteCount) * 24
        let delta = CGSize(width: point.x - anchor.x + cascade, height: point.y - anchor.y + cascade)
        func shifted(_ c: CGPoint) -> CGPoint { CGPoint(x: c.x + delta.width, y: c.y + delta.height) }

        var newSelection = Set<UUID>()
        transaction {
            for entry in clipboard {
                if isCut { pasteCutEntry(entry, into: targetDir, shift: shifted, select: &newSelection) }
                else { pasteCopyEntry(entry, into: targetDir, vault: vault, shift: shifted, select: &newSelection) }
            }
        }
        guard !newSelection.isEmpty else { return }
        selection = newSelection
        selectedEdge = nil
        editingId = nil
        if isCut { clipboard = []; clipboardIsCut = false; cutIds = [] } else { pasteCount += 1 }
    }

    private func pasteCopyEntry(_ entry: ClipboardEntry, into targetDir: String, vault: Vault,
                                shift: (CGPoint) -> CGPoint, select: inout Set<UUID>) {
        let src = entry.node
        let ext = src.kind == .folder ? "" : "md"
        let newRel = vault.uniqueRel(dir: targetDir, base: src.name + " copy", ext: ext)
        tCopy(src.relPath, newRel)   // duplicates the file (or whole folder subtree) on disk
        var root = src
        root.id = UUID()
        root.relPath = newRel
        root.center = shift(src.center)
        board.nodes.append(root)
        select.insert(root.id)
        // Recreate boxes for the duplicated subtree; their files already exist from the copyItem.
        for d in entry.descendants where d.relPath.hasPrefix(src.relPath + "/") {
            var dn = d
            dn.id = UUID()
            dn.relPath = newRel + String(d.relPath.dropFirst(src.relPath.count))
            dn.center = shift(d.center)
            board.nodes.append(dn)
        }
    }

    private func pasteCutEntry(_ entry: ClipboardEntry, into targetDir: String,
                               shift: (CGPoint) -> CGPoint, select: inout Set<UUID>) {
        guard let idx = board.nodes.firstIndex(where: { $0.id == entry.node.id }) else { return }
        let live = board.nodes[idx]
        // Don't move a folder into itself or its own subtree.
        if live.kind == .folder, targetDir == live.relPath || targetDir.hasPrefix(live.relPath + "/") { return }
        board.nodes[idx].center = shift(live.center)
        // Carry the subtree's boxes along (reposition by the same delta).
        for d in entry.descendants {
            if let di = board.nodes.firstIndex(where: { $0.id == d.id }) {
                board.nodes[di].center = shift(board.nodes[di].center)
            }
        }
        // Re-file on disk if the target folder differs.
        if live.parentRel != targetDir {
            let name = (live.relPath as NSString).lastPathComponent
            let newRel = targetDir.isEmpty ? name : "\(targetDir)/\(name)"
            if vault?.exists(newRel) == true {
                NSSound.beep()   // name clash: keep it where it is, just repositioned
            } else {
                let oldRel = live.relPath
                tMove(oldRel, newRel)
                board.nodes[idx].relPath = newRel
                if live.kind == .folder { reparentChildren(oldPrefix: oldRel, newPrefix: newRel) }
            }
        }
        select.insert(live.id)
    }

    // MARK: Peek (inline file content)

    /// Open the content peek for a box (notes only — folders have no content).
    func openPeek(_ id: UUID) {
        guard let n = node(id), n.kind == .note else { return }
        selection = [id]
        editingId = nil
        selectedEdge = nil
        peekId = id
    }
    func closePeek() { peekId = nil }
    func togglePeek(_ id: UUID) { if peekId == id { peekId = nil } else { openPeek(id) } }

    /// Expand/collapse a note into an in-place content card. Expanding grows it to a comfortable size
    /// (keeping any larger custom size); collapsing returns it to the default note size. Undoable.
    func setExpanded(_ id: UUID, _ on: Bool) {
        guard let idx = board.nodes.firstIndex(where: { $0.id == id }), board.nodes[idx].kind == .note else { return }
        guard (board.nodes[idx].expanded ?? false) != on else { return }
        transaction {
            board.nodes[idx].expanded = on
            if on {
                board.nodes[idx].width = max(board.nodes[idx].width, AppModel.expandedSize.width)
                board.nodes[idx].height = max(board.nodes[idx].height, AppModel.expandedSize.height)
            } else {
                board.nodes[idx].width = gappDefaultNoteSize.width
                board.nodes[idx].height = gappDefaultNoteSize.height
            }
        }
    }
    func toggleExpand(_ id: UUID) {
        guard let n = node(id) else { return }
        setExpanded(id, !(n.expanded ?? false))
    }

    /// Current text content of a box's backing file ("" if unreadable).
    func fileText(_ id: UUID) -> String {
        guard let vault, let n = node(id) else { return "" }
        return (try? String(contentsOf: vault.url(n.relPath), encoding: .utf8)) ?? ""
    }

    private func rawWrite(_ rel: String, _ text: String) {
        guard let vault else { return }
        markSelfWrite(rel)
        try? text.data(using: .utf8)?.write(to: vault.url(rel), options: .atomic)
    }

    /// Save edited content back to a box's file as one undoable step (no-op if unchanged).
    func saveFileContent(_ id: UUID, _ text: String) {
        guard vault != nil, let n = node(id), n.kind == .note else { return }
        let rel = n.relPath
        let old = fileText(id)
        guard old != text else { return }
        transaction {
            rawWrite(rel, text)
            txnFileRedo.append { self.rawWrite(rel, text) }
            txnFileUndo.append { self.rawWrite(rel, old) }
        }
    }

    /// Apply a pure text transform to a file and record the write so it's reversed with the rest of
    /// the active transaction (one undo step covers board + disk). No-op if the transform changes
    /// nothing. Must run inside an open `transaction`.
    private func rewriteFile(_ rel: String, _ transform: (String) -> String) {
        guard let vault else { return }
        let old = (try? String(contentsOf: vault.url(rel), encoding: .utf8)) ?? ""
        let new = transform(old)
        guard new != old else { return }
        rawWrite(rel, new)
        txnFileRedo.append { self.rawWrite(rel, new) }
        txnFileUndo.append { self.rawWrite(rel, old) }
    }

    func setPosition(_ id: UUID, to center: CGPoint) {
        guard let idx = board.nodes.firstIndex(where: { $0.id == id }) else { return }
        board.nodes[idx].center = CGPoint(x: AppModel.clampCoord(center.x),
                                          y: AppModel.clampCoord(center.y))
    }

    func setFrame(_ id: UUID, _ frame: CGRect) {
        guard let idx = board.nodes.firstIndex(where: { $0.id == id }) else { return }
        board.nodes[idx].width = AppModel.clampSize(frame.width, fallback: gappDefaultNoteSize.width)
        board.nodes[idx].height = AppModel.clampSize(frame.height, fallback: gappDefaultNoteSize.height)
        board.nodes[idx].center = CGPoint(x: AppModel.clampCoord(frame.midX),
                                          y: AppModel.clampCoord(frame.midY))
    }

    /// The set of boxes that move together when `id` is dragged. If `id` is part of a multi-selection,
    /// every selected box moves; otherwise just `id`. Either way, a moving folder carries all of its
    /// descendant boxes (any depth). De-duplicated.
    func dragGroup(for id: UUID) -> Set<UUID> {
        let base: Set<UUID> = (selection.contains(id) && selection.count > 1) ? selection : [id]
        var ids = base
        for n in board.nodes where base.contains(n.id) && n.kind == .folder {
            for d in board.nodes where d.relPath.hasPrefix(n.relPath + "/") { ids.insert(d.id) }
        }
        return ids
    }

    /// Build a resized frame from a fixed `anchor` corner and the dragged corner (`sign` is the
    /// drag's direction from the anchor, ±1 per axis). Clamps so the box never goes below `minSize`
    /// and — for a folder with contents — never shrinks past the children it holds. Resizing a
    /// folder moves only its own frame; the contents stay put (no rescaling).
    func resizedFrame(for node: BoardNode, anchor: CGPoint, drag rawDrag: CGPoint,
                      sign: CGVector, minSize: CGSize) -> CGRect {
        // Keep the dragged corner on its own side of the anchor (never flip past it).
        var drag = CGPoint(x: sign.dx > 0 ? max(rawDrag.x, anchor.x) : min(rawDrag.x, anchor.x),
                           y: sign.dy > 0 ? max(rawDrag.y, anchor.y) : min(rawDrag.y, anchor.y))
        if node.kind == .folder, let cb = contentsBounds(of: node) {
            if sign.dx > 0 { drag.x = max(drag.x, cb.maxX) } else { drag.x = min(drag.x, cb.minX) }
            if sign.dy > 0 { drag.y = max(drag.y, cb.maxY) } else { drag.y = min(drag.y, cb.minY) }
        }
        // Enforce the minimum size, growing away from the fixed anchor.
        if abs(drag.x - anchor.x) < minSize.width  { drag.x = anchor.x + sign.dx * minSize.width }
        if abs(drag.y - anchor.y) < minSize.height { drag.y = anchor.y + sign.dy * minSize.height }
        return CGRect(x: min(anchor.x, drag.x), y: min(anchor.y, drag.y),
                      width: abs(drag.x - anchor.x), height: abs(drag.y - anchor.y))
    }

    /// Set (or clear, when `color == nil`) the accent of one or more boxes. Undoable.
    func setColor(_ ids: Set<UUID>, _ color: BoxColor?) {
        guard !ids.isEmpty else { return }
        transaction {
            for id in ids where board.nodes.contains(where: { $0.id == id }) {
                let idx = board.nodes.firstIndex { $0.id == id }!
                board.nodes[idx].colorName = color?.rawValue
            }
        }
    }

    /// Set the title text size of one or more boxes. Undoable.
    func setTextSize(_ ids: Set<UUID>, _ size: TextSize) {
        guard !ids.isEmpty else { return }
        transaction {
            for id in ids where board.nodes.contains(where: { $0.id == id }) {
                let idx = board.nodes.firstIndex { $0.id == id }!
                board.nodes[idx].fontScale = Double(size.scale)
            }
        }
    }

    // MARK: Connectors

    /// A note whose body can hold a `[[wikilink]]` — i.e. a markdown file. Only these participate in
    /// the connector ↔ link bridge; CSV/code notes and folders get a visual-only edge for now.
    private func isLinkable(_ node: BoardNode) -> Bool {
        node.kind == .note && node.fileType == .markdown
    }

    /// Make the directed edge `from → to` a real link on disk: add `[[to]]` to `from`'s managed
    /// canvas-links block. No-op unless both ends are markdown notes. Must run inside a transaction.
    private func writeLink(from: BoardNode, to: BoardNode) {
        guard isLinkable(from), isLinkable(to) else { return }
        rewriteFile(from.relPath) { text in
            ManagedLinks.write(ManagedLinks.targets(in: text) + [to.name], into: text)
        }
    }

    /// Remove the `[[to]]` link from `from`'s managed block (the inverse of `writeLink`).
    private func removeLink(from: BoardNode, to: BoardNode) {
        guard isLinkable(from), isLinkable(to) else { return }
        rewriteFile(from.relPath) { text in
            ManagedLinks.write(ManagedLinks.targets(in: text).filter { $0 != to.name }, into: text)
        }
    }

    /// Select a connector, clearing any box selection / rename in progress.
    func selectEdge(_ id: UUID) {
        selection = []
        editingId = nil
        selectedEdge = id
    }

    func clearEdgeSelection() { selectedEdge = nil }

    /// Create a connector between two boxes (no duplicates, no self-loops). Undoable.
    @discardableResult
    func connect(from: UUID, to: UUID) -> Bool {
        guard from != to,
              node(from) != nil, node(to) != nil,
              !board.edges.contains(where: { ($0.from == from && $0.to == to) ||
                                             ($0.from == to && $0.to == from) }) else { return false }
        transaction {
            let edge = BoardEdge(from: from, to: to)
            board.edges.append(edge)
            if let a = node(from), let b = node(to) { writeLink(from: a, to: b) }
            selection = []
            editingId = nil
            selectedEdge = edge.id
        }
        return true
    }

    func deleteEdge(_ id: UUID) {
        guard let edge = board.edges.first(where: { $0.id == id }) else { return }
        transaction {
            if let a = node(edge.from), let b = node(edge.to) { removeLink(from: a, to: b) }
            board.edges.removeAll { $0.id == id }
            if selectedEdge == id { selectedEdge = nil }
        }
    }

    private func mutateEdge(_ id: UUID, _ change: (inout BoardEdge) -> Void) {
        guard let idx = board.edges.firstIndex(where: { $0.id == id }) else { return }
        transaction { change(&board.edges[idx]) }
    }

    func setEdgeColor(_ id: UUID, _ color: BoxColor?) { mutateEdge(id) { $0.colorName = color?.rawValue } }
    func setEdgeStyle(_ id: UUID, _ style: EdgeStyle) { mutateEdge(id) { $0.styleRaw = style.rawValue } }
    func setEdgeDirected(_ id: UUID, _ on: Bool) { mutateEdge(id) { $0.directed = on } }

    // MARK: Navigation

    func center(on id: UUID) {
        guard let n = node(id) else { return }
        selection = [id]
        selectedEdge = nil
        guard viewport != .zero else { return }
        pan = CGSize(width: viewport.width / 2 - n.x * zoom,
                     height: viewport.height / 2 - n.y * zoom)
    }

    /// Center the view on existing content (or world center) the first time we have a size.
    func initViewIfNeeded() {
        guard !didInitView, viewport != .zero else { return }
        didInitView = true
        let target: CGPoint
        if board.nodes.isEmpty {
            target = CGPoint(x: 10000, y: 10000)
        } else {
            let avgX = board.nodes.map { $0.x }.reduce(0, +) / Double(board.nodes.count)
            let avgY = board.nodes.map { $0.y }.reduce(0, +) / Double(board.nodes.count)
            target = CGPoint(x: avgX, y: avgY)
        }
        pan = CGSize(width: viewport.width / 2 - target.x * zoom,
                     height: viewport.height / 2 - target.y * zoom)
    }

    // MARK: Reveal helpers

    func revealInFinder(_ id: UUID) {
        guard let vault, let n = node(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([vault.url(n.relPath)])
    }

    func openInDefaultApp(_ id: UUID) {
        guard let vault, let n = node(id) else { return }
        NSWorkspace.shared.open(vault.url(n.relPath))
    }
}
