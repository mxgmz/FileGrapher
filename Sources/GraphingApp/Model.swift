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
    var expanded: Bool?          // shown as an in-place content card; nil/false == title-only
    var collapsed: Bool?         // folder with its children hidden on the canvas; nil/false == open
    var cardSize: CGSize?        // remembered expanded-card size, so it survives collapse/re-expand
    var fileId: UInt64?          // disk inode — lets syncFromDisk follow a box to a file's new path
    var pinned: Bool?            // anchored: can't be dragged, and collision push never moves it; nil/false == free
    var scrollOffset: CGSize?    // open folder: how far its interior is scrolled (nil == .zero), a transient view nudge

    /// True when this box is showing content inline as a card (notes, and folders via their folder-note).
    var isExpanded: Bool { expanded ?? false }

    /// True when this folder is collapsed (children hidden, frame shrunk to its header).
    var isCollapsedFolder: Bool { kind == .folder && (collapsed ?? false) }

    /// True when this folder is OPEN — its interior children show and scroll inside its card.
    var isOpenFolder: Bool { kind == .folder && !(collapsed ?? false) }

    /// How far this folder's interior is scrolled (.zero when never nudged).
    var scroll: CGSize { scrollOffset ?? .zero }

    /// True when this box is anchored: it can't be dragged and the push solver treats it as an
    /// immovable obstacle that siblings route around.
    var isPinned: Bool { pinned ?? false }

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
    var linkBacked: Bool?    // true == this edge IS a `[[wikilink]]` on disk (read side owns it); nil == a
                             // hand-drawn visual edge the link-reconcile must never delete
    var label: String?       // a user-typed connector label ("depends on"); nil == unlabelled

    var style: EdgeStyle { EdgeStyle(rawValue: styleRaw ?? "") ?? .curved }
    var isDirected: Bool { directed ?? true }
    var color: Color {
        if let colorName, let c = BoxColor(rawValue: colorName) { return c.color }
        return Color.secondary.opacity(0.6)
    }
}

/// A folder-level connector synthesized by edge promotion (SPEC-folder-canvas.md §4): when an endpoint
/// is hidden inside a collapsed folder it is re-anchored to that folder, and parallel links collapse into
/// one connector whose `weight` is how many real links it stands in for. Render-only — never on disk.
struct PromotedEdge: Identifiable {
    let from: UUID
    let to: UUID
    let weight: Int
    var id: String { "\(from)->\(to)" }
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

/// A transient, render-only ghost for a file that existed at the viewed commit but is gone from the
/// working tree now (the "fade in" half of the time-travel structure diff). NOT a `BoardNode` — it
/// isn't on disk or in `board.json` and is never selected/dragged; it only visualizes "this used to be
/// here." Position is best-effort (no stored layout for a deleted file).
struct HistoryGhost: Identifiable, Equatable {
    let id: String        // the file's vault-relative path (stable within one commit view)
    let name: String
    let center: CGPoint
    let size: CGSize
}

/// A `[[link]]` that existed at the viewed commit but isn't drawn now — rendered as a faded ghost
/// connector between the two surviving notes. Render-only, never hit-tested (the time-travel link diff).
struct GhostEdge: Identifiable, Equatable {
    let id: String        // order-independent node-pair key
    let from: UUID
    let to: UUID
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {
    @Published var vault: Vault?
    @Published var board = BoardData()
    /// In-app MCP server letting an external agent drive the canvas (docs/SPEC-mcp-cartographer.md).
    let mcp = MCPServer()
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

    /// Routing lock for a scroll gesture that pans an OPEN folder's interior instead of the canvas
    /// (decided once at the gesture's start, held for its duration — same reason as `scrollOverCard`).
    /// A wrapped value distinguishes "decided: this folder" / "decided: no folder (pan canvas)" / nil.
    /// Input-only (not @Published).
    var scrollFolderTarget: UUID??

    // MARK: Live file-watching (the read side of the living canvas)

    /// Bumps whenever a watched file's content may have changed (our own write or an external edit in
    /// Obsidian / by an agent). Open content cards & peeks observe this and re-read from disk.
    @Published private(set) var diskRevision = 0
    private var watcher: VaultWatcher?
    /// Vault-relative paths the app itself just wrote, with the time of the write — so the watcher can
    /// tell our own echo from a genuine external change and not loop or re-sync needlessly.
    private var selfWrites: [String: Date] = [:]

    /// Vault-relative paths of notes whose card/peek is being edited right now. The edit-guarded
    /// re-read silently drops an external change to one of these (so the next save would clobber it),
    /// so we track them to detect that conflict and raise the reload banner instead.
    private var editingPaths: Set<String> = []
    /// Notes that changed on disk *externally* while their card/peek was in edit mode — the banner
    /// shows on each of these until the user reloads (discard local edits) or dismisses (keep editing).
    @Published private(set) var diskConflicts: Set<String> = []

    // MARK: Version history (git time-travel — VIEW-ONLY)

    /// True when the open vault is a git repo (version history enabled). Mirrors `GitService.isRepo`.
    @Published private(set) var versionHistoryEnabled = false
    /// Newest-first commits of the vault, for the history panel.
    @Published private(set) var commits: [GitService.Commit] = []
    /// Uncommitted changes in the working tree, so the UI can tell whether a Snapshot would do anything.
    @Published private(set) var uncommittedCount = 0
    /// Local branch names and the current one (for branch-preview, P3).
    @Published private(set) var branches: [String] = []
    @Published private(set) var currentBranch = ""
    /// The branch whose tip is being previewed as a ghost overlay (nil == not previewing a branch). When
    /// set, `viewedCommit` holds that branch ref and the structure diff reads against the live board.
    @Published private(set) var previewedBranch: String?
    /// A git operation (enable / snapshot / refresh) is running off the main thread.
    @Published private(set) var gitBusy = false

    /// The commit whose content the canvas is currently showing, or nil for the live working tree.
    /// VIEW-ONLY time-travel (P1): only card/peek *content* changes — boxes never move and disk is
    /// never written while a past commit is viewed.
    @Published private(set) var viewedCommit: String?
    /// relPath → that file's content at `viewedCommit` (a nil value means the file didn't exist there).
    /// Loaded off the main thread when a commit is selected, so cards can read historical text fast.
    private var historicalContent: [String: String?] = [:]
    /// Render-only ghosts for files that existed at `viewedCommit` but are gone now (deleted-since).
    @Published private(set) var historyGhosts: [HistoryGhost] = []
    /// Render-only ghost connectors for `[[links]]` that existed at `viewedCommit` but aren't drawn now.
    @Published private(set) var historyGhostEdges: [GhostEdge] = []
    /// Current link edges whose link didn't exist at `viewedCommit` — drawn dimmed/dashed ("added later").
    @Published private(set) var historyAddedEdges: Set<UUID> = []

    var isTimeTraveling: Bool { viewedCommit != nil }

    /// A view-only git client for the open vault, or nil when no vault is open.
    private var gitService: GitService? { vault.map { GitService(root: $0.root) } }

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

    /// One-time **v1 → v2 migration** (SPEC-folder-canvas.md §1): reinterpret every stored `x,y` from a
    /// GLOBAL center to one stored RELATIVE to its parent folder's center. Uses a *snapshot* of the
    /// original globals (not freshly-written values) so nested nodes convert correctly regardless of
    /// order. Lossless + reversible: after migration `worldCenter(of:)` reproduces the original global
    /// exactly (asserted in Tests/RelativeCoordTests.swift). No-op once `version >= 2`. Run before any
    /// world-derivation on the freshly loaded board; resave when it runs.
    @discardableResult
    func migrateToRelativeIfNeeded() -> Bool {
        guard board.version < 2 else { return false }
        let originalGlobal = Dictionary(uniqueKeysWithValues: board.nodes.map { ($0.id, $0.center) })
        for i in board.nodes.indices {
            let node = board.nodes[i]
            // Root nodes keep their value (global == relative-to-origin); nested ones become a delta from
            // the parent's ORIGINAL global, so the parent's own (later) rewrite can't corrupt the math.
            if let parent = parentFolder(of: node),
               let parentGlobal = originalGlobal[parent.id], let nodeGlobal = originalGlobal[node.id] {
                board.nodes[i].center = CGPoint(x: nodeGlobal.x - parentGlobal.x,
                                                y: nodeGlobal.y - parentGlobal.y)
            }
        }
        board.version = 2
        Log.disk.notice("Migrated board.json to v2 (relative coordinates) — \(self.board.nodes.count, privacy: .public) nodes.")
        return true
    }

    /// One-time **v2 → v3 migration** (Folder-Canvas Phase 2, folder-as-card): seed each folder's stored
    /// card frame from its CURRENT auto-grown frame, so retiring auto-grow renders identically on first
    /// open. Same snapshot-preserves-nesting trick as `migrateToRelativeIfNeeded`: compute every folder's
    /// old footprint on the pre-mutation board, then for each folder move its WORLD center onto that
    /// footprint's center and counter-shift its direct children by the same delta. Net effect: nothing's
    /// rendered position moves — a leaf's `worldCenter` is preserved, and a folder's `worldFrame` becomes
    /// its old auto-grown frame (the folder's OWN center intentionally shifts onto that off-center
    /// footprint, which is the whole point — it now IS the card). No-op once `version >= 3`. Run right
    /// after `migrateToRelativeIfNeeded`; resave when it runs.
    @discardableResult
    func seedFolderCardsIfNeeded() -> Bool {
        guard board.version < 3 else { return false }
        let folderIDs = board.nodes.filter { $0.kind == .folder }.map { $0.id }
        // Snapshot each folder's OPEN auto-grown footprint on the CURRENT board, before any move. Open
        // (asOpenCard) so a COLLAPSED folder's card is seeded to its content extent — the size it must
        // expand back to — not its collapsed header strip (which would render fine but expand to nothing).
        let grown = Dictionary(uniqueKeysWithValues:
            board.nodes.filter { $0.kind == .folder }.map { ($0.id, legacyAutoGrownFrame(of: $0, asOpenCard: true)) })
        // Iterate by id and re-read the LIVE node each pass: a folder may already have been counter-shifted
        // by its parent's seed, so `worldCenter` must read the current board, never a stale pre-loop copy.
        for id in folderIDs {
            guard let index = board.nodes.firstIndex(where: { $0.id == id }), let target = grown[id] else { continue }
            let folder = board.nodes[index]
            // delta moves the folder's WORLD center onto the footprint's center.
            let worldBefore = worldCenter(of: folder)
            let delta = CGPoint(x: target.midX - worldBefore.x, y: target.midY - worldBefore.y)
            board.nodes[index].width = AppModel.clampSize(target.width, fallback: gappDefaultNoteSize.width)
            board.nodes[index].height = AppModel.clampSize(target.height, fallback: gappDefaultNoteSize.height)
            // F's stored center is RELATIVE; shifting it by delta moves F's world center by delta too.
            board.nodes[index].center = CGPoint(x: AppModel.clampCoord(board.nodes[index].x + delta.x),
                                                y: AppModel.clampCoord(board.nodes[index].y + delta.y))
            // Counter-shift each DIRECT child so its (and its subtree's) world position is preserved.
            for child in directChildren(of: folder.relPath) {
                guard let childIndex = board.nodes.firstIndex(where: { $0.id == child.id }) else { continue }
                board.nodes[childIndex].center = CGPoint(x: AppModel.clampCoord(board.nodes[childIndex].x - delta.x),
                                                         y: AppModel.clampCoord(board.nodes[childIndex].y - delta.y))
            }
        }
        board.version = 3
        Log.disk.notice("Migrated board.json to v3 (folder cards) — seeded \(folderIDs.count, privacy: .public) folders.")
        return true
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

            // Children are stored relative to this folder, so their median is the cluster center in the
            // folder's OWN local space; pull egregious outliers back toward it (siblings, so distances are
            // space-invariant). We never re-anchor the folder itself onto that median — post-migration the
            // children already orbit the folder's center, so doing so would yank the folder to its parent's
            // origin (the v1-global-era re-anchor that caused a deep-subfolder→(0,0) cascade).
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
            changed = true
        }
        if changed {
            Log.canvas.notice("Reined in stranded folder children on load — a box was far enough from its siblings to balloon its folder.")
        }
        return changed
    }

    /// Move a box (and its whole subtree, rigid-body) so the box lands at `center`. Coordinates clamped.
    /// Move a node (and, implicitly, its whole subtree) to a new center in its PARENT's local space.
    /// Post-migration the children are stored relative to this node, so changing only the node's own
    /// center carries them along — the old prefix-shift of every descendant is gone (SPEC §3).
    private func moveSubtree(_ id: UUID, to center: CGPoint) {
        setPosition(id, to: center)
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

    /// A world rect mapped into screen space (origin + size scaled by zoom, translated by pan).
    func worldRectToScreen(_ r: CGRect) -> CGRect {
        let origin = worldToScreen(r.origin)
        return CGRect(x: origin.x, y: origin.y, width: r.width * zoom, height: r.height * zoom)
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

    /// Zoom limits. Scroll/pinch and the keyboard/menu zoom all clamp to this range so the canvas can
    /// never zoom past the readable extremes (and pan stays reachable — see `panBound`'s 4× assumption).
    static let minZoom: CGFloat = 0.2
    static let maxZoom: CGFloat = 4
    /// Multiplier per ⌘+ / ⌘− step (and the TopBar magnifier buttons).
    static let zoomStep: CGFloat = 1.2

    static func clampZoom(_ v: CGFloat) -> CGFloat { min(max(v, minZoom), maxZoom) }

    /// Zoom while keeping the world point under `screenPoint` fixed (cursor-anchored zoom).
    func zoomToward(_ screenPoint: CGPoint, factor: CGFloat) {
        let newZoom = AppModel.clampZoom(zoom * factor)
        guard abs(newZoom - zoom) > .ulpOfOne else { return }
        let w = screenToWorld(screenPoint)
        zoom = newZoom
        pan = CGSize(width: screenPoint.x - w.x * newZoom,
                     height: screenPoint.y - w.y * newZoom)
    }

    /// Keyboard/menu/TopBar zoom: scale by `factor`, anchored on the viewport center (cursor-anchoring
    /// is only for scroll/pinch, which have a natural focus point; a keystroke does not).
    func zoomBy(_ factor: CGFloat) {
        guard viewport != .zero else { return }
        zoomToward(CGPoint(x: viewport.width / 2, y: viewport.height / 2), factor: factor)
    }

    func zoomIn() { zoomBy(AppModel.zoomStep) }
    func zoomOut() { zoomBy(1 / AppModel.zoomStep) }

    /// ⌘0 / click-the-percent: back to exactly 100%, re-centered on existing content (or world center).
    func resetZoom() {
        zoom = 1
        recenterOnContent()
    }

    /// Pan so the average of all node centers sits at the viewport center, at the current zoom. Empty
    /// board → the world origin used at first launch. Shared by `resetZoom` and the initial view.
    private func recenterOnContent() {
        guard viewport != .zero else { return }
        let target: CGPoint
        if board.nodes.isEmpty {
            target = CGPoint(x: 10000, y: 10000)
        } else {
            let centers = board.nodes.map { worldCenter(of: $0) }   // average WORLD centers, not relative
            let avgX = centers.map(\.x).reduce(0, +) / Double(centers.count)
            let avgY = centers.map(\.y).reduce(0, +) / Double(centers.count)
            target = CGPoint(x: avgX, y: avgY)
        }
        pan = CGSize(width: viewport.width / 2 - target.x * zoom,
                     height: viewport.height / 2 - target.y * zoom)
    }

    /// World-space bounding box of everything on the board (each node's `effectiveFrame`, so a folder
    /// counts at its grown size), or nil when the board is empty.
    func boardBounds() -> CGRect? {
        guard let first = board.nodes.first else { return nil }
        var bounds = effectiveFrame(of: first)
        for node in board.nodes.dropFirst() { bounds = bounds.union(effectiveFrame(of: node)) }
        return bounds
    }

    /// Pan + zoom so every node fits on screen with a margin. Empty board → reset to 100% centered
    /// (never divides by zero). The fit zoom is clamped to [`minZoom`, `maxZoom`].
    func zoomToFit(padding: CGFloat = 80) {
        guard viewport != .zero else { return }
        guard let bounds = boardBounds(), bounds.width > 0, bounds.height > 0 else {
            resetZoom(); return
        }
        let fitX = (viewport.width - 2 * padding) / bounds.width
        let fitY = (viewport.height - 2 * padding) / bounds.height
        zoom = AppModel.clampZoom(min(fitX, fitY))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        pan = CGSize(width: viewport.width / 2 - center.x * zoom,
                     height: viewport.height / 2 - center.y * zoom)
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
        // Migrate global→relative coords FIRST (v1→v2), before anything derives a world position.
        let migrated = migrateToRelativeIfNeeded()
        // Then seed folder cards (v2→v3): freeze each folder's current auto-grown frame as its stored
        // card, so retiring auto-grow renders identically. Runs after the relative migration (it relies
        // on worldCenter being correct) and on the same resave.
        let seeded = seedFolderCardsIfNeeded()
        // Self-heal a corrupt board before it can hang or become unusable: clamp runaway coords, then
        // pull any stranded folder child back so no folder auto-grows to an unclickable size.
        let repaired = sanitizeBoardGeometry()
        let healed = reinInStrandedChildren()
        if migrated || seeded || repaired || healed { v.saveBoard(board) }
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
        clearHistory()
        syncFromDisk()
        didInitView = false
        startWatching()
        refreshVersionHistory()
        mcp.start(model: self)
    }

    func closeVault() {
        stopWatching()
        mcp.stop()
        vault = nil
        board = BoardData()
        selection = []
        versionHistoryEnabled = false
        commits = []
        uncommittedCount = 0
        branches = []
        currentBranch = ""
        previewedBranch = nil
        viewedCommit = nil
        historicalContent = [:]
        historyGhosts = []
        historyGhostEdges = []
        historyAddedEdges = []
        editingPaths = []
        diskConflicts = []
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

    // MARK: Conflict reload banner (external change while editing a card/peek)

    /// A card/peek entered edit mode for `id`'s note. Track it so an external change to that file
    /// (which the edit-guard would otherwise silently swallow) raises the reload banner.
    func beginEditingFile(_ id: UUID) {
        guard let n = node(id) else { return }
        editingPaths.insert(contentRel(for: n))
    }

    /// A card/peek left edit mode (saved, cancelled, collapsed, or closed). Stop watching it for a
    /// conflict and clear any banner already raised — once you're no longer editing, there's nothing
    /// unsaved to clobber.
    func endEditingFile(_ id: UUID) {
        guard let n = node(id) else { return }
        let rel = contentRel(for: n)
        editingPaths.remove(rel)
        diskConflicts.remove(rel)
    }

    func hasDiskConflict(_ id: UUID) -> Bool {
        guard let n = node(id) else { return false }
        return diskConflicts.contains(contentRel(for: n))
    }

    /// Resolve a conflict by discarding local edits: clear the flag so the caller re-reads disk.
    func clearDiskConflict(_ id: UUID) {
        guard let n = node(id) else { return }
        diskConflicts.remove(contentRel(for: n))
    }

    /// React to a debounced batch of changed vault-relative paths from the watcher.
    func handleDiskChange(_ rels: [String]) {
        guard vault != nil else { return }
        // Our own board.json sidecar, and git's `.git/` + `.gitignore` plumbing, aren't user content.
        let relevant = rels.filter { !$0.hasPrefix(".graphingapp") && !$0.hasPrefix(".git") }
        guard !relevant.isEmpty else { return }
        // Any content change (ours or external) → open cards/peeks re-read. The views guard against
        // clobbering an in-progress edit; re-reading after our own link-write is what makes a drawn
        // connector's `[[link]]` appear live in the source note's card.
        diskRevision &+= 1
        // An EXTERNAL change to a file whose card/peek is mid-edit would be silently dropped by that
        // edit-guard (and clobbered by the next save), so flag it for the reload banner — but never
        // while time-traveling (git history is read-only, no live conflict possible).
        if !isTimeTraveling {
            for rel in relevant where editingPaths.contains(rel) && !isRecentSelfWrite(rel) {
                diskConflicts.insert(rel)
            }
        }
        // Reconcile structure (new/deleted/moved boxes) only for EXTERNAL changes — our own
        // create/move/trash already updated the board in its transaction — and never mid-interaction,
        // so a drag/resize isn't yanked out from under the user.
        let hasExternal = relevant.contains { !isRecentSelfWrite($0) }
        // Also hold the rebuild while the user is typing in a card/peek/rename field: mutating
        // board.nodes under an open editor churns the view and can strand keyboard focus, leaving you
        // unable to edit anything else. The deferred reconcile catches up on the next change / manual ↻.
        let isTypingInField = editingId != nil || NSApp.keyWindow?.firstResponder is NSText
        if hasExternal, interactionBefore == nil, !isTypingInField { syncFromDisk() }
    }

    // MARK: Version history operations (off the main thread — git can block)

    /// The displayable git state, loaded together so one background hop refreshes the whole panel.
    private struct GitState: Sendable {
        var enabled: Bool
        var commits: [GitService.Commit]
        var uncommitted: Int
        var branches: [String]
        var currentBranch: String
    }

    /// Read git state off the main actor. `nonisolated` so it can run on a detached task.
    nonisolated private static func loadGitState(_ git: GitService) -> GitState {
        let enabled = git.isRepo
        return GitState(enabled: enabled,
                        commits: enabled ? git.commits() : [],
                        uncommitted: enabled ? git.uncommittedChangeCount() : 0,
                        branches: enabled ? git.branches() : [],
                        currentBranch: enabled ? git.currentBranch() : "")
    }

    private func apply(_ state: GitState) {
        versionHistoryEnabled = state.enabled
        commits = state.commits
        uncommittedCount = state.uncommitted
        branches = state.branches
        currentBranch = state.currentBranch
        gitBusy = false
    }

    /// Detect whether the open vault has version history and load its commits. Cheap; safe to re-call.
    func refreshVersionHistory() {
        guard let git = gitService else {
            apply(GitState(enabled: false, commits: [], uncommitted: 0, branches: [], currentBranch: ""))
            return
        }
        runGit { AppModel.loadGitState(git) }
    }

    /// Opt in to version history: `git init` + ignore the layout sidecar + a baseline commit.
    func enableVersionHistory() {
        guard let git = gitService, !versionHistoryEnabled else { return }
        Log.disk.notice("enabling version history (git init) for the vault")
        runGit { _ = git.enableVersionHistory(); return AppModel.loadGitState(git) }
    }

    /// Commit the current working tree on demand (manual Snapshot), then refresh the commit list.
    func snapshot() {
        guard let git = gitService, versionHistoryEnabled else { return }
        Log.disk.notice("taking a version-history snapshot")
        runGit { _ = git.snapshot(); return AppModel.loadGitState(git) }
    }

    /// Run a git `work` block off the main thread (it can block on disk), then apply the resulting
    /// state on the main actor. `gitBusy` gates overlapping operations and drives the panel spinner.
    private func runGit(_ work: @escaping @Sendable () -> GitState) {
        guard !gitBusy else { return }
        gitBusy = true
        Task.detached { [weak self] in
            let state = work()
            await self?.apply(state)   // `apply` is main-actor-isolated; this hops back on its own
        }
    }

    // MARK: Time-travel (view a past commit's content — positions stay fixed, disk untouched)

    /// Switch the canvas to a past commit's content (or back to live when `hash` is nil). Loads each
    /// note's content at that commit off the main thread, then refreshes open cards/peeks via
    /// `diskRevision`. Box positions never change — only what the content surfaces render.
    /// View a past commit on the current branch (the scrubber). `nil` returns to the live working tree.
    func viewCommit(_ hash: String?) { setViewedRevision(hash, branch: nil) }

    /// Preview another branch's tip as a ghost overlay (P3). `nil` exits back to live. A branch name is a
    /// valid git revision, so the same content + structure-diff machinery as the commit scrubber applies:
    /// files only on the branch appear as deleted-since ghosts, files not on it dim as added-later.
    func previewBranch(_ name: String?) { setViewedRevision(name, branch: name) }

    /// Show a git revision (a commit hash, or a branch ref when `branch` is set) — or the live working
    /// tree when `revision` is nil. Loads each note's content + the file list at that revision off the
    /// main thread, then refreshes cards/ghosts. Box positions never move; disk is never written.
    private func setViewedRevision(_ revision: String?, branch: String?) {
        guard revision != viewedCommit || branch != previewedBranch else { return }
        previewedBranch = branch
        viewedCommit = revision
        guard let revision, let git = gitService else {
            historicalContent = [:]
            historyGhosts = []
            historyGhostEdges = []
            historyAddedEdges = []
            diskRevision &+= 1   // back to live: cards re-read from disk
            return
        }
        let rels = board.nodes.filter { $0.kind == .note }.map(\.relPath)
        gitBusy = true
        Task.detached { [weak self] in
            var cache: [String: String?] = [:]
            // updateValue (not subscript) so an absent file stores a real nil rather than dropping the key.
            for rel in rels { cache.updateValue(git.show(rel, at: revision), forKey: rel) }
            let tracked = git.filesAtCommit(revision)
            await self?.applyHistory(content: cache, trackedAtCommit: tracked)
        }
    }

    private func applyHistory(content: [String: String?], trackedAtCommit: [String]) {
        historicalContent = content
        historyGhosts = deletedSinceGhosts(trackedAtCommit: trackedAtCommit)
        let (added, ghostEdges) = historyEdgeDiff()
        historyAddedEdges = added
        historyGhostEdges = ghostEdges
        gitBusy = false
        diskRevision &+= 1   // open cards/peeks re-read → historical text
    }

    /// Ghosts for files tracked at the viewed commit but absent from the working tree now. Positioned
    /// best-effort — stacked just below a surviving parent folder, else tiled near the viewport center.
    private func deletedSinceGhosts(trackedAtCommit: [String]) -> [HistoryGhost] {
        let liveRels = Set(board.nodes.map(\.relPath))
        let deleted = trackedAtCommit
            .filter { AppModel.boxableExts.contains(($0 as NSString).pathExtension.lowercased()) }
            .filter { !liveRels.contains($0) }
            .sorted()
        var countByParent: [String: Int] = [:]
        return deleted.map { rel in
            let parent = (rel as NSString).deletingLastPathComponent
            let index = countByParent[parent, default: 0]
            countByParent[parent] = index + 1
            let display = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
            return HistoryGhost(id: rel, name: display,
                                center: ghostCenter(parentRel: parent, index: index),
                                size: AppModel.noteSize)
        }
    }

    private func ghostCenter(parentRel: String, index: Int) -> CGPoint {
        let columns = 3
        let dx = CGFloat(index % columns) * (AppModel.noteSize.width + 22)
        let dy = CGFloat(index / columns) * (AppModel.noteSize.height + 22)
        if !parentRel.isEmpty,
           let folder = board.nodes.first(where: { $0.kind == .folder && $0.relPath == parentRel }) {
            let frame = effectiveFrame(of: folder)   // stack beneath the surviving folder
            let x = frame.minX + AppModel.noteSize.width / 2 + dx
            let y = frame.maxY + AppModel.noteSize.height / 2 + 20 + dy
            return CGPoint(x: AppModel.clampCoord(x), y: AppModel.clampCoord(y))
        }
        let center = screenToWorld(CGPoint(x: viewport.width / 2, y: viewport.height / 2))
        return CGPoint(x: AppModel.clampCoord(center.x - 220 + dx),
                       y: AppModel.clampCoord(center.y + 140 + dy))
    }

    /// True while viewing history when the node's file did not exist at the viewed commit.
    func isAbsentInHistory(_ id: UUID) -> Bool {
        guard isTimeTraveling, let n = node(id) else { return false }
        if let content = historicalContent[n.relPath] { return content == nil }
        return false   // not loaded yet → not (yet) known absent
    }

    /// True while viewing history when this link edge's `[[link]]` did not exist at the viewed commit.
    func isEdgeAbsentInHistory(_ id: UUID) -> Bool { historyAddedEdges.contains(id) }

    /// The link diff for the viewed commit, parsed from the already-loaded `historicalContent` (no extra
    /// git calls): current link edges whose `[[link]]` is absent there (→ dim), and links present there
    /// but not drawn now (→ ghost in). Both endpoints must still resolve to surviving notes.
    private func historyEdgeDiff() -> (added: Set<UUID>, ghosts: [GhostEdge]) {
        guard isTimeTraveling else { return ([], []) }
        let resolve = linkTargetResolver()
        var historicalPairs = Set<String>()
        var historicalLinks: [(from: UUID, to: UUID)] = []
        for n in board.nodes where isLinkable(n) {
            guard let text = historicalContent[n.relPath].flatMap({ $0 }) else { continue }
            for target in ManagedLinks.targets(in: text) {
                guard let toId = resolve(target), toId != n.id else { continue }
                historicalPairs.insert(unorderedPairKey(n.id, toId))
                historicalLinks.append((n.id, toId))
            }
        }
        var currentPairs = Set<String>()
        var added = Set<UUID>()
        for edge in board.edges where edge.linkBacked == true {
            let key = unorderedPairKey(edge.from, edge.to)
            currentPairs.insert(key)
            if !historicalPairs.contains(key) { added.insert(edge.id) }
        }
        var ghosts: [GhostEdge] = []
        var seen = Set<String>()
        for link in historicalLinks {
            let key = unorderedPairKey(link.from, link.to)
            guard !currentPairs.contains(key), seen.insert(key).inserted else { continue }
            ghosts.append(GhostEdge(id: key, from: link.from, to: link.to))
        }
        return (added, ghosts)
    }

    var vaultName: String { vault?.root.lastPathComponent ?? "No Vault" }

    // MARK: Disk <-> board sync

    /// Dependency/build output directories that are noise, not notes: opening a code repo as a vault
    /// otherwise boxes thousands of vendored files (one observed case made ~145 `node_modules` boxes).
    /// `.git`/`.build` are already skipped by `.skipsHiddenFiles`; these aren't hidden, so we skip them
    /// (and their whole subtree) by name during the enumerator walk.
    static let vendorDirNames: Set<String> = [
        "node_modules", ".build", "dist", "build", "vendor", "Pods",
        ".next", "target", "__pycache__", ".venv", "venv",
    ]
    static func isVendorDir(_ name: String) -> Bool { vendorDirNames.contains(name) }

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
                if isDir, AppModel.isVendorDir(fileURL.lastPathComponent) {
                    en.skipDescendants()   // don't box the vendor dir or anything inside it
                    continue
                }
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
        // corner, which used to strand them and balloon the folder's auto-grown frame. A folder-note
        // (`<FolderName>.md` inside its folder) is the folder box's own content, not a separate box.
        let folderNoteRels = Set(board.nodes.filter { $0.kind == .folder }.map { folderNoteRel(for: $0) })
        for (index, rel) in diskRels.subtracting(known).subtracting(folderNoteRels).sorted().enumerated() {
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
        reconcileLinkEdges()
        save()
    }

    /// Read side of the living-canvas link bridge: each note's managed `<!-- canvas-links -->` block is
    /// the source of truth for the edges between notes. A `[[Target]]` written into the block — by the
    /// app, an agent, or another machine — gets an edge here; a link removed there drops its edge. Edges
    /// with any non-note endpoint, and pre-link hand-drawn note edges (`linkBacked == nil`), are never
    /// touched. **Ambiguity-safe:** a name shared by several notes (the live vault's many "Untitled")
    /// never auto-draws a guessed edge, and an existing edge is kept as long as *some* link of that name
    /// is still in the source's block — so a user's edge to an ambiguous target isn't destroyed.
    /// ponytail: re-reads every note file each sync — fine at this vault scale; cache by mtime if it bites.
    private func reconcileLinkEdges() {
        guard let vault else { return }
        let resolve = linkTargetResolver()

        // The link-name strings listed in each note's managed block, read from disk.
        var blockNames: [UUID: Set<String>] = [:]
        for node in board.nodes where isLinkable(node) {
            guard let text = try? String(contentsOf: vault.url(node.relPath), encoding: .utf8) else { continue }
            let names = Set(ManagedLinks.targets(in: text))
            if !names.isEmpty { blockNames[node.id] = names }
        }
        // The names by which a target node could be addressed in a block (bare or path-qualified).
        func names(of node: BoardNode) -> [String] {
            [node.name, (node.relPath as NSString).deletingPathExtension]
        }

        // 1. Keep / upgrade / drop existing note↔note edges against the blocks on disk.
        var covered = Set<String>()
        var rebuilt: [BoardEdge] = []
        for var edge in board.edges {
            guard let a = node(edge.from), let b = node(edge.to), isLinkable(a), isLinkable(b) else {
                rebuilt.append(edge); continue        // any non-note endpoint → visual edge, untouched
            }
            let linkPresent = blockNames[a.id].map { block in names(of: b).contains { block.contains($0) } } ?? false
            if !linkPresent && edge.linkBacked == true { continue }   // a real link, now gone → drop it
            if linkPresent { edge.linkBacked = true }                 // confirm/upgrade a still-present link
            covered.insert(unorderedPairKey(a.id, b.id))              // keep (legacy or still-linked)
            rebuilt.append(edge)
        }
        board.edges = rebuilt

        // 2. Auto-draw an edge for each block link that resolves uniquely and has no edge yet.
        for (sourceId, targets) in blockNames {
            for target in targets {
                guard let toId = resolve(target), toId != sourceId,
                      covered.insert(unorderedPairKey(sourceId, toId)).inserted else { continue }
                board.edges.append(BoardEdge(from: sourceId, to: toId, linkBacked: true))
            }
        }
    }

    /// A resolver from a wikilink target string to a unique current note id — `[[Name]]` by basename,
    /// `[[folder/Name]]` by path — refusing a name shared by several notes (the live vault's many
    /// "Untitled"), so no wrong edge is ever guessed. Shared by the read-side reconcile and the link diff.
    private func linkTargetResolver() -> (String) -> UUID? {
        var idByName: [String: UUID] = [:]
        var ambiguous = Set<String>()
        var idByPath: [String: UUID] = [:]
        for n in board.nodes where isLinkable(n) {
            idByPath[(n.relPath as NSString).deletingPathExtension] = n.id
            if idByName[n.name] != nil { ambiguous.insert(n.name) } else { idByName[n.name] = n.id }
        }
        return { target in idByPath[target] ?? (ambiguous.contains(target) ? nil : idByName[target]) }
    }

    /// Order-independent key for a node pair, so an edge and its reverse count as the same connection.
    private func unorderedPairKey(_ a: UUID, _ b: UUID) -> String {
        [a.uuidString, b.uuidString].sorted().joined(separator: "|")
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
        // Result is stored directly as the new node's center, so it must be in the PARENT's local space.
        let anchor: CGPoint
        if let sibling = directChildren(of: parent).first {
            anchor = CGPoint(x: sibling.center.x + 150, y: sibling.center.y)   // beside an existing sibling
        } else {
            // No sibling: aim for the viewport center, expressed in the parent's local space.
            let world = viewport != .zero
                ? screenToWorld(CGPoint(x: viewport.width / 2, y: viewport.height / 2))
                : CGPoint(x: 10000, y: 10000)
            anchor = relativeCenter(world, inDir: parent)
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
        let hidden = hiddenNodeIds
        return board.nodes
            .compactMap { node -> (node: BoardNode, area: CGFloat)? in
                guard !hidden.contains(node.id), include(node) else { return nil }
                // Hit-test against the DRAWN rect (effectiveFrame shifted by any scrolled ancestors) and
                // honor the clip: a child scrolled out of an open-folder ancestor's card window is hidden
                // on screen, so it must not be hittable there either.
                let frame = displayedFrame(of: node)
                guard frame.contains(point), isVisibleThroughCards(node, at: point) else { return nil }
                return (node, frame.width * frame.height)
            }
            .min { $0.area < $1.area }?.node
    }

    /// True when `point` (world) lies within every OPEN ancestor folder's DRAWN card-interior window —
    /// i.e. the node isn't clipped away by a card it lives inside. Each ancestor's interior is shifted by
    /// that ancestor's own `renderOffset` (a nested card is itself scrolled by its parents), matching the
    /// render-side `.clipped()` exactly.
    private func isVisibleThroughCards(_ node: BoardNode, at point: CGPoint) -> Bool {
        var current = node
        var depth = 0
        var seen = Set<String>([node.relPath])
        while let parent = parentFolder(of: current) {
            guard depth < AppModel.maxFolderDepth, seen.insert(parent.relPath).inserted else { break }
            if parent.isOpenFolder {
                let shift = renderOffset(of: parent)
                let window = cardInterior(of: parent).offsetBy(dx: shift.width, dy: shift.height)
                if !window.contains(point) { return false }
            }
            current = parent
            depth += 1
        }
        return true
    }

    /// The OPEN folder whose card interior a scroll over `point` should pan — the smallest (most specific)
    /// open folder whose displayed interior window contains the point. nil → scroll pans the canvas. Used
    /// by the input monitor to route two-finger scroll: over an open folder's interior, it scrolls that
    /// folder's children; elsewhere it pans.
    func scrollTargetFolder(at point: CGPoint) -> BoardNode? {
        let hidden = hiddenNodeIds
        return board.nodes
            .filter { $0.isOpenFolder && !hidden.contains($0.id) }
            .filter { folder in
                let shift = renderOffset(of: folder)
                let interior = cardInterior(of: folder).offsetBy(dx: shift.width, dy: shift.height)
                return interior.contains(point) && isVisibleThroughCards(folder, at: point)
            }
            .min { let a = effectiveFrame(of: $0), b = effectiveFrame(of: $1)
                   return a.width * a.height < b.width * b.height }
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

    /// Minimum-translation vector that pushes `mover` out of `obstacle` along the shorter axis of
    /// their overlap — the smallest nudge that just separates two AABBs. Zero when they don't overlap.
    static func separationVector(_ mover: CGRect, outOf obstacle: CGRect) -> CGSize {
        guard mover.intersects(obstacle) else { return .zero }
        let overlap = mover.intersection(obstacle)
        if overlap.width <= overlap.height {
            let dx = mover.midX < obstacle.midX ? -overlap.width : overlap.width
            return CGSize(width: dx, height: 0)
        }
        let dy = mover.midY < obstacle.midY ? -overlap.height : overlap.height
        return CGSize(width: 0, height: dy)
    }

    /// Settle the board after `movedId` was dropped/grown/resized: keep the moved box where it is and
    /// **push overlapping siblings aside** (min-translation, cascading to their neighbors) until no two
    /// siblings' `effectiveFrame`s intersect. SIBLINGS only (same `parentRel`) — a folder must contain
    /// its own children, so parent↔child never "collides". A **pinned** sibling never moves: it's an
    /// obstacle the push routes around. If the mover itself is boxed in by pinned siblings (can't stay
    /// without overlapping one), fall back to `nearestFreeCenter` for the mover so we never deadlock.
    /// All sibling moves run before the caller's `commit`, so they ride its single undo step.
    func resolveOverlaps(movedId: UUID) {
        guard let mover = node(movedId) else { return }
        let moverFrame = effectiveFrame(of: mover)

        // Deadlock guard: a pinned sibling can't be pushed, so if the mover overlaps one it must move
        // itself. Snap it (and its subtree) to the nearest gap clear of ALL siblings, then stop.
        let pinnedFrames = board.nodes
            .filter { $0.parentRel == mover.parentRel && $0.id != movedId && $0.isPinned }
            .map { effectiveFrame(of: $0) }
        if pinnedFrames.contains(where: { $0.intersects(moverFrame) }) {
            if let free = nearestFreeCenter(for: movedId, near: mover.center), free != mover.center {
                moveSubtree(movedId, to: free)
            }
            return
        }

        // Working centers for every same-parent box; the mover is the fixed seed (never re-placed here).
        let siblings = board.nodes.filter { $0.parentRel == mover.parentRel }
        var center: [UUID: CGPoint] = Dictionary(uniqueKeysWithValues: siblings.map { ($0.id, $0.center) })
        let baseFrame: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: siblings.map { ($0.id, effectiveFrame(of: $0)) })
        func frame(_ id: UUID) -> CGRect {
            let base = baseFrame[id]!, c = center[id]!, n = node(id)!
            return base.offsetBy(dx: c.x - n.center.x, dy: c.y - n.center.y)
        }
        let pushable = siblings.filter { $0.id != movedId && !$0.isPinned }.map { $0.id }

        // Capped relaxation: each pass pushes every movable sibling out of its deepest current overlap.
        // Bounded so the cascade (and folder auto-grow re-collisions) can never spin the CPU; a residual
        // overlap is acceptable — far better than a hang.
        for _ in 0..<24 {
            var moved = false
            for id in pushable {
                let me = frame(id)
                // Push out of whichever sibling we overlap most (the mover and pinned boxes included).
                var worst: (CGRect, CGFloat) = (.null, 0)
                for other in siblings where other.id != id {
                    let f = frame(other.id)
                    let area = me.intersection(f)
                    let depth = min(area.width, area.height)
                    if me.intersects(f), depth > worst.1 { worst = (f, depth) }
                }
                guard worst.1 > 0 else { continue }
                let push = AppModel.separationVector(me, outOf: worst.0)
                guard push != .zero else { continue }
                center[id] = CGPoint(x: AppModel.clampCoord(center[id]!.x + push.width),
                                     y: AppModel.clampCoord(center[id]!.y + push.height))
                moved = true
            }
            if !moved { break }
        }

        // Commit the deltas: translate each pushed sibling (folders carry their whole subtree).
        for id in pushable {
            let delta = CGSize(width: center[id]!.x - node(id)!.center.x,
                               height: center[id]!.y - node(id)!.center.y)
            if abs(delta.width) > 0.5 || abs(delta.height) > 0.5 { moveSubtree(id, to: center[id]!) }
        }
    }

    /// Boxes whose parent folder is exactly `relPath` (one level down).
    func directChildren(of relPath: String) -> [BoardNode] {
        board.nodes.filter { $0.parentRel == relPath }
    }

    /// A child farther than this from its siblings' cluster (their median) is a far-flung outlier and is
    /// EXCLUDED from its folder's auto-grow — so one scattered box can't balloon the folder; it just renders
    /// loose, outside the frame. Tuned (on the real recordentaln8n board) to catch only genuine outliers
    /// (~2% of boxes): many children legitimately stacked tall are NOT outliers, since each sits near its
    /// neighbors. (Folder-Canvas Phase 2 — "bound auto-grow", the minimal step before folder-as-card.)
    static let autoGrowOutlierRadius: CGFloat = 6000

    /// Direct children that count toward a folder's auto-grown frame: all of them, minus far-flung outliers.
    /// Falls back to all children if the filter would leave none (degenerate: every child its own outlier).
    /// ponytail: medians per call (effectiveFrame is hot); fine at this scale — memoize if a huge vault bites.
    private func autoGrowChildren(of node: BoardNode) -> [BoardNode] {
        let children = directChildren(of: node.relPath)
        guard children.count > 1 else { return children }
        let mx = median(children.map { $0.center.x }), my = median(children.map { $0.center.y })
        let near = children.filter { hypot($0.center.x - mx, $0.center.y - my) <= AppModel.autoGrowOutlierRadius }
        return near.isEmpty ? children : near
    }

    // MARK: World coordinates (relative storage → absolute derivation — SPEC-folder-canvas.md §0–2)
    //
    // A node's stored `x,y` is its center *relative to its parent folder's center* (root nodes: relative
    // to the world origin, so their stored value already IS world). Absolute position is **derived** by
    // summing the ancestor chain. This is the single place that derivation lives — `effectiveFrame` and
    // every world-reader route through it, so the ~115 position-reads didn't have to change.
    // ponytail: recomputes the chain per call (no memo). Boards are shallow + node counts modest; add a
    // revision-keyed cache (SPEC §7) only if a deep/huge vault profiles slow.

    /// The folder a node lives directly inside, or nil at the vault root.
    func parentFolder(of node: BoardNode) -> BoardNode? {
        let parent = node.parentRel
        guard !parent.isEmpty else { return nil }
        return board.nodes.first { $0.kind == .folder && $0.relPath == parent }
    }

    /// A folder's anchor in world space = its own world center (its children are stored relative to it).
    func worldOrigin(of folder: BoardNode) -> CGPoint { worldCenter(of: folder) }

    /// Absolute (world) center of a node: its relative center plus every ancestor folder's, to the root.
    /// The sum telescopes because each level's stored center is relative to the next level up.
    func worldCenter(of node: BoardNode) -> CGPoint {
        var x = node.x, y = node.y
        var current = node
        var depth = 0
        var seen = Set<String>([node.relPath])   // cycle guard, mirrors effectiveFrame's
        while let parent = parentFolder(of: current) {
            guard depth < AppModel.maxFolderDepth, seen.insert(parent.relPath).inserted else {
                warnFolderCycle(at: parent.relPath, depth: depth); break
            }
            x += parent.x; y += parent.y
            current = parent
            depth += 1
        }
        return CGPoint(x: x, y: y)
    }

    /// World-space frame of a node (its size centered on its world center). Replaces `node.frame` for
    /// any read that needs absolute coordinates; `effectiveFrame` is built on it.
    func worldFrame(of node: BoardNode) -> CGRect {
        let c = worldCenter(of: node)
        return CGRect(x: c.x - node.width / 2, y: c.y - node.height / 2, width: node.width, height: node.height)
    }

    /// Convert a world point to a center stored relative to `dir` (the parent folder; "" == root). The
    /// one conversion the write paths need when a box is created in, or re-parented into, a folder.
    func relativeCenter(_ world: CGPoint, inDir dir: String) -> CGPoint {
        guard !dir.isEmpty, let folder = board.nodes.first(where: { $0.kind == .folder && $0.relPath == dir })
        else { return world }
        let o = worldOrigin(of: folder)
        return CGPoint(x: world.x - o.x, y: world.y - o.y)
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

    /// Render the board (or one folder's contents) to a PNG for the agent's vision-feedback loop
    /// (docs/SPEC-mcp-cartographer.md phase 5). Schematic — boxes as rounded rects + titles, edges as lines —
    /// which is all an agent needs to judge *layout* (overlap, balance, clustering), not the live chrome.
    /// ponytail: in-process schematic render, no screen-recording permission. Upgrade to real-window capture
    /// only if the agent must see actual card content/styling.
    @MainActor func renderBoardPNG(scope: String?, maxPixels: CGFloat = 1200) -> Data? {
        let inScope: (BoardNode) -> Bool = { node in
            guard let scope, !scope.isEmpty else { return true }
            return node.parentRel == scope || node.relPath == scope || node.relPath.hasPrefix(scope + "/")
        }
        // Respect collapsed folders: their children are hidden on the canvas, so don't draw them (or
        // their edges) — else the picture shows a density the user can't actually see at normal zoom.
        let collapsedPrefixes = board.nodes.filter { $0.isCollapsedFolder }.map { $0.relPath + "/" }
        func hidden(_ node: BoardNode) -> Bool { collapsedPrefixes.contains { node.relPath.hasPrefix($0) } }
        let nodes = board.nodes.filter { inScope($0) && !hidden($0) }
        guard let first = nodes.first else { return nil }

        var bounds = effectiveFrame(of: first)
        for node in nodes.dropFirst() { bounds = bounds.union(effectiveFrame(of: node)) }
        bounds = bounds.insetBy(dx: -60, dy: -60)
        let scale = min(maxPixels / max(bounds.width, bounds.height), 1)
        let pxW = max(bounds.width * scale, 1), pxH = max(bounds.height * scale, 1)

        // World is y-down (box centers); AppKit image space is y-up — flip vertically.
        func img(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - bounds.minX) * scale, y: pxH - (p.y - bounds.minY) * scale) }
        func imgRect(_ r: CGRect) -> CGRect {
            CGRect(x: (r.minX - bounds.minX) * scale, y: pxH - (r.maxY - bounds.minY) * scale,
                   width: r.width * scale, height: r.height * scale)
        }

        let image = NSImage(size: CGSize(width: pxW, height: pxH))
        image.lockFocus()
        NSColor(white: 0.97, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: pxW, height: pxH)).fill()

        func drawNode(_ node: BoardNode) {
            let rect = imgRect(effectiveFrame(of: node))
            let isFolder = node.kind == .folder
            // Surface the agent's canvas_color coding: a colored node fills with its palette color
            // (folders as a light wash so children stay legible, notes as a soft tint), falling back
            // to the fixed folder-blue / note-white only when the node has no color set.
            let fill: NSColor
            if let colorName = node.colorName, let boxColor = BoxColor(rawValue: colorName) {
                let palette = NSColor(boxColor.color)
                fill = palette.withAlphaComponent(isFolder ? 0.18 : 0.30)
            } else {
                fill = isFolder ? NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.99, alpha: 1) : .white
            }
            fill.setFill()
            (node.isExpanded ? NSColor.systemBlue : NSColor(white: 0.55, alpha: 1)).setStroke()
            let box = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            box.fill(); box.lineWidth = node.isExpanded ? 2.5 : 1.5; box.stroke()

            let fontSize = max(8, min(rect.height * 0.28, 18))
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.black]
            let title = node.name as NSString
            let size = title.size(withAttributes: attrs)
            // Folder title hugs the top (it's a header); a note's title centers in the box.
            let ty = isFolder ? rect.maxY - size.height - 4 : rect.midY - size.height / 2
            title.draw(at: CGPoint(x: rect.midX - size.width / 2, y: ty), withAttributes: attrs)
        }

        // Z-order mirrors the canvas: folders (containers) at the back, then connectors, then notes on top —
        // otherwise a folder's fill paints over the edges inside it.
        for node in nodes where node.kind == .folder { drawNode(node) }

        let byId = Dictionary(board.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        NSColor(white: 0.5, alpha: 1).setStroke()
        for edge in board.edges {
            guard let a = byId[edge.from], let b = byId[edge.to],
                  (inScope(a) || inScope(b)), !hidden(a), !hidden(b) else { continue }
            let line = NSBezierPath()
            line.move(to: img(worldCenter(of: a))); line.line(to: img(worldCenter(of: b)))
            line.lineWidth = 1.5; line.stroke()
        }

        for node in nodes where node.kind == .note { drawNode(node) }

        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Max nesting we'll ever walk before assuming the graph is pathological.
    private static let maxFolderDepth = 256
    private var lastFolderCycleWarning: Date?

    private func effectiveFrame(of node: BoardNode, visited: inout Set<String>, depth: Int) -> CGRect {
        guard node.kind == .folder else { return worldFrame(of: node) }
        // Folder-as-card (Folder-Canvas Phase 2): a folder's footprint is now its own stored card
        // frame — a fixed viewport — NOT a union of its contents. Auto-grow is retired (its old union
        // lives on in `legacyAutoGrownFrame`, used only by the v2→v3 seed). Collapsed still collapses.
        if node.isCollapsedFolder { return collapsedFrame(of: node) }
        // Cycle / runaway guard, kept intact even though the recursion is gone: a corrupt board (a
        // folder that is its own ancestor) must still bail loudly instead of spinning, and a later PR
        // may reintroduce recursion here.
        guard depth < AppModel.maxFolderDepth, visited.insert(node.relPath).inserted else {
            warnFolderCycle(at: node.relPath, depth: depth)
            return worldFrame(of: node)
        }
        return worldFrame(of: node)
    }

    /// The OLD auto-grow footprint: a folder's stored frame unioned with its children's own
    /// auto-grown frames (plus padding + header), collapsed folders short-circuiting to their header.
    /// A faithful replica of the pre-Phase-2 `effectiveFrame` behavior, kept ONLY so the v2→v3 seed
    /// migration can snapshot what each folder used to display before retiring auto-grow.
    ///
    /// `asOpenCard` forces the TOP folder open even when it's collapsed: the seed needs a folder's OPEN
    /// content extent for its card size (the size it must expand back to), which is distinct from its
    /// collapsed *rendering* (`effectiveFrame` → `collapsedFrame`, the header strip). Nested children
    /// still reflect their own actual collapse state, so a collapsed child contributes only its header.
    func legacyAutoGrownFrame(of node: BoardNode, asOpenCard: Bool = false) -> CGRect {
        var visited = Set<String>()
        return legacyAutoGrownFrame(of: node, visited: &visited, depth: 0, asOpenCard: asOpenCard)
    }

    private func legacyAutoGrownFrame(of node: BoardNode, visited: inout Set<String>, depth: Int, asOpenCard: Bool) -> CGRect {
        guard node.kind == .folder else { return worldFrame(of: node) }
        if node.isCollapsedFolder && !asOpenCard { return collapsedFrame(of: node) }
        guard depth < AppModel.maxFolderDepth, visited.insert(node.relPath).inserted else {
            warnFolderCycle(at: node.relPath, depth: depth)
            return worldFrame(of: node)
        }
        var frame = worldFrame(of: node)
        let children = autoGrowChildren(of: node)   // exclude far-flung outliers so one box can't balloon the folder
        if !children.isEmpty {
            // Children recurse with asOpenCard:false — a collapsed CHILD still contributes only its
            // collapsed header to the parent's footprint (it's the open extent OF THE TOP folder we want).
            var bounds = legacyAutoGrownFrame(of: children[0], visited: &visited, depth: depth + 1, asOpenCard: false)
            for child in children.dropFirst() {
                bounds = bounds.union(legacyAutoGrownFrame(of: child, visited: &visited, depth: depth + 1, asOpenCard: false))
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

    /// Width a collapsed folder shrinks to: its header (title + the "N items" badge), never wider
    /// than its stored frame so collapse only ever shrinks.
    private static let collapsedFolderWidth: CGFloat = 220

    /// A collapsed folder's frame: just the header strip, anchored at the stored (world) top-left.
    func collapsedFrame(of node: BoardNode) -> CGRect {
        let wf = worldFrame(of: node)
        let width = min(wf.width, AppModel.collapsedFolderWidth)
        return CGRect(x: wf.minX, y: wf.minY, width: width, height: AppModel.folderHeaderHeight)
    }

    // MARK: Folder-as-card scroll viewport (Folder-Canvas Phase 2 · PR-2)
    //
    // An OPEN folder is a fixed-size card that *clips* its children to its bounds. When the card is
    // smaller than its content, two-finger scrolling over the interior pans the children inside the
    // card. Scroll is a transient view nudge (like canvas pan) — it shifts where children RENDER, never
    // their stored layout — so it lives outside `effectiveFrame`'s un-scrolled world coordinates.

    /// The world rect a folder's children occupy — the content the card scrolls over. Reuses the
    /// retired auto-grow union (PR-1's `legacyAutoGrownFrame`, the open content footprint) so the card
    /// and its scroll clamp agree on "everything inside".
    func contentExtent(of folder: BoardNode) -> CGRect {
        legacyAutoGrownFrame(of: folder, asOpenCard: true)
    }

    /// How far a node is shifted when drawn, because one or more OPEN ancestor folders are scrolled:
    /// the sum of every open ancestor's `scrollOffset` up the chain. A collapsed ancestor contributes
    /// nothing (its children are hidden anyway). A child of a scrolled folder rides this offset.
    func renderOffset(of node: BoardNode) -> CGSize {
        var offset = CGSize.zero
        var current = node
        var depth = 0
        var seen = Set<String>([node.relPath])
        while let parent = parentFolder(of: current) {
            guard depth < AppModel.maxFolderDepth, seen.insert(parent.relPath).inserted else { break }
            if parent.isOpenFolder { offset.width += parent.scroll.width; offset.height += parent.scroll.height }
            current = parent
            depth += 1
        }
        return offset
    }

    /// A node's displayed (drawn) world frame: its `effectiveFrame` shifted by `renderOffset`. Render
    /// and hit-test BOTH route through this, so a scrolled child is hit where it's drawn. (Layout reads
    /// — push, marquee, bounds — keep using the un-scrolled `effectiveFrame`.)
    func displayedFrame(of node: BoardNode) -> CGRect {
        effectiveFrame(of: node).offsetBy(dx: renderOffset(of: node).width, dy: renderOffset(of: node).height)
    }

    /// The scrollable interior of an OPEN folder's card in world space: its frame minus the header strip
    /// (the header + border don't scroll — only the interior children do, and the card clips to here).
    func cardInterior(of folder: BoardNode) -> CGRect {
        let frame = effectiveFrame(of: folder)
        let header = AppModel.folderHeaderHeight
        return CGRect(x: frame.minX, y: frame.minY + header, width: frame.width, height: max(0, frame.height - header))
    }

    /// The DRAWN-world rect a node is clipped to: the intersection of every OPEN ancestor folder's
    /// drawn card interior (each shifted by its own `renderOffset`). nil when the node has no open-folder
    /// ancestor (a root box is never clipped). The render side masks each child to this window so content
    /// overflowing a shrunk folder card is hidden until scrolled into view.
    func clipWindow(of node: BoardNode) -> CGRect? {
        var window: CGRect?
        var current = node
        var depth = 0
        var seen = Set<String>([node.relPath])
        while let parent = parentFolder(of: current) {
            guard depth < AppModel.maxFolderDepth, seen.insert(parent.relPath).inserted else { break }
            if parent.isOpenFolder {
                let shift = renderOffset(of: parent)
                let interior = cardInterior(of: parent).offsetBy(dx: shift.width, dy: shift.height)
                window = window?.intersection(interior) ?? interior
            }
            current = parent
            depth += 1
        }
        return window
    }

    /// Nudge an open folder's interior by `delta`, clamped so it can never scroll past its content. On
    /// each axis the offset stays within `[min(0, interior − content) … 0]`: 0 when the content already
    /// fits (nothing to reveal), else just enough negative shift to bring the far edge into view. A
    /// transient view nudge — NOT undoable (don't route through `transaction`); just set + `save()` so it
    /// persists like a pan.
    func scrolledFolder(_ id: UUID, by delta: CGSize) {
        guard let index = board.nodes.firstIndex(where: { $0.id == id }),
              board.nodes[index].isOpenFolder else { return }
        let interior = cardInterior(of: board.nodes[index]).size
        let content = contentExtent(of: board.nodes[index]).size
        let current = board.nodes[index].scroll
        let clamped = AppModel.clampScroll(CGSize(width: current.width + delta.width,
                                                  height: current.height + delta.height),
                                           interior: interior, content: content)
        board.nodes[index].scrollOffset = (clamped == .zero) ? nil : clamped
        save()
    }

    /// Clamp a folder's interior scroll offset to its content. Pure (no model state) so the headless
    /// `Tests/FolderScrollClampTests.swift` can port exactly this math. Per axis: an axis whose content
    /// fits the interior (`content <= interior`) pins at 0; otherwise the offset is bounded to
    /// `[interior − content … 0]` (0 == top/left edge, `interior − content` == bottom/right edge flush).
    static func clampScroll(_ offset: CGSize, interior: CGSize, content: CGSize) -> CGSize {
        func axis(_ value: CGFloat, _ visible: CGFloat, _ extent: CGFloat) -> CGFloat {
            extent <= visible ? 0 : min(0, max(visible - extent, value))
        }
        return CGSize(width: axis(offset.width, interior.width, content.width),
                      height: axis(offset.height, interior.height, content.height))
    }

    /// Boxes hidden from render / hit-test / marquee because an ancestor folder is collapsed. They
    /// stay in `board.json`, `dragGroup`, `delete`, and `syncFromDisk` — only the canvas ignores them.
    var hiddenNodeIds: Set<UUID> {
        let collapsedPrefixes = board.nodes.filter { $0.isCollapsedFolder }.map { $0.relPath + "/" }
        guard !collapsedPrefixes.isEmpty else { return [] }
        var ids = Set<UUID>()
        for node in board.nodes where collapsedPrefixes.contains(where: { node.relPath.hasPrefix($0) }) {
            ids.insert(node.id)
        }
        return ids
    }

    func isHidden(_ id: UUID) -> Bool { hiddenNodeIds.contains(id) }

    /// Number of boxes living anywhere inside a folder (for the collapsed "N items" badge).
    func descendantCount(of node: BoardNode) -> Int {
        board.nodes.filter { $0.relPath.hasPrefix(node.relPath + "/") }.count
    }

    /// Folder-level connectors for the collapsed view (SPEC-folder-canvas.md §4). Pure over the board's
    /// `collapsed` flags: re-anchor each edge endpoint to its outermost collapsed ancestor, drop links
    /// internal to one collapsed folder, and merge parallels into one weighted connector. Returns ONLY the
    /// synthesized edges (≥1 endpoint promoted) — edges among fully visible boxes keep their real
    /// interactive connectors, drawn elsewhere.
    /// ponytail: recomputed per render; memoize per collapse-state only if a huge edge count bites (§7).
    var promotedEdges: [PromotedEdge] { AppModel.promotedEdges(nodes: board.nodes, edges: board.edges) }

    static func promotedEdges(nodes: [BoardNode], edges: [BoardEdge]) -> [PromotedEdge] {
        // Outermost first: a node's visible stand-in is its shallowest collapsed ancestor (the only one not
        // itself hidden); a deeper collapsed folder nested inside it never surfaces.
        let collapsedFolders = nodes.filter { $0.isCollapsedFolder }.sorted { $0.relPath.count < $1.relPath.count }
        guard !collapsedFolders.isEmpty else { return [] }
        let byId = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func representative(_ id: UUID) -> UUID? {
            guard let node = byId[id] else { return nil }
            return collapsedFolders.first { node.relPath.hasPrefix($0.relPath + "/") }?.id ?? id
        }

        var weights: [String: PromotedEdge] = [:]
        var order: [String] = []
        for edge in edges {
            guard let from = representative(edge.from), let to = representative(edge.to),
                  from != to,                                  // internal to one collapsed folder → drop
                  from != edge.from || to != edge.to          // neither endpoint moved → a real edge, drawn as-is
            else { continue }
            let key = "\(from)->\(to)"
            if let merged = weights[key] {
                weights[key] = PromotedEdge(from: from, to: to, weight: merged.weight + 1)
            } else {
                weights[key] = PromotedEdge(from: from, to: to, weight: 1)
                order.append(key)
            }
        }
        return order.map { weights[$0]! }
    }

    /// Collapse / expand a folder (hide or show its descendants). Undoable.
    func toggleCollapse(_ id: UUID) {
        guard let idx = board.nodes.firstIndex(where: { $0.id == id }),
              board.nodes[idx].kind == .folder else { return }
        transaction { board.nodes[idx].collapsed = !(board.nodes[idx].collapsed ?? false) }
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
    /// Module-internal (not `private`) so same-module cartographer extensions (MCPServer.swift) can bundle
    /// their mutations into one ⌘Z step — the same guarantee every UI mutation already gets.
    func transaction(_ body: () -> Void) {
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

    /// End a corner-resize: a box grown on resize can now overlap siblings, so push them aside before
    /// committing — the push rides this resize's single undo step (same as the drop case).
    func endResize(_ id: UUID) {
        guard let before = interactionBefore else { return }
        interactionBefore = nil
        resolveOverlaps(movedId: id)
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
            // Keep the box where the user dropped it: convert its world center into the new parent's
            // local space (children are relative to it, so they travel along untouched).
            let worldBefore = worldCenter(of: board.nodes[idx])
            board.nodes[idx].relPath = newRel
            board.nodes[idx].center = relativeCenter(worldBefore, inDir: newDir)
            if current.kind == .folder { reparentChildren(oldPrefix: oldRel, newPrefix: newRel) }
        }

        // Re-file by where the cursor dropped, not the box center — so a box can land in a small
        // nested folder even when the box's own center never reaches it.
        if let folder = reFileFolder(under: dropPoint, for: id) {
            if folder.relPath != current.parentRel { relocate(to: folder.relPath) }
        } else if current.parentRel != "" {
            relocate(to: "")
        }

        // Settle on drop: keep the box where the user let go and PUSH overlapped siblings aside (pinned
        // ones stay put; the mover snaps to a gap only if it's boxed in by pinned siblings). Runs after
        // any re-file so siblings are measured in the box's final folder; the whole push rides this
        // drag's single undo step. Only new drops settle — existing overlaps on load are left untouched.
        resolveOverlaps(movedId: id)

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
            let stored = relativeCenter(center, inDir: dir)   // `center` is world; store relative to `dir`
            let node = BoardNode(kind: .note, relPath: rel,
                                 x: stored.x, y: stored.y,
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
            let stored = relativeCenter(center, inDir: dir)   // `center` is world; store relative to `dir`
            let node = BoardNode(kind: .folder, relPath: rel,
                                 x: stored.x, y: stored.y,
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
        var c = worldCenter(of: node)   // place the sibling in world space; addNote/addFolder store relative
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
                let sibling = self.node(newId)
                let real = isLinkable(node) && sibling.map { isLinkable($0) } == true
                board.edges.append(BoardEdge(from: node.id, to: newId, linkBacked: real ? true : nil))
                if let sibling { writeLink(from: node, to: sibling) }
            }
        }
    }

    /// Add a note inside a folder (used by the folder header "+" button).
    @discardableResult
    func addChildNote(inFolder folder: BoardNode) -> UUID? {
        let count = board.nodes.filter { $0.parentRel == folder.relPath }.count
        // Tile inside the folder's interior, in world space (addNote stores it relative to the folder).
        let wc = worldCenter(of: folder)
        let x = wc.x - folder.width / 2 + 56 + CGFloat(count % 3) * 150
        let y = wc.y - folder.height / 2 + 70 + CGFloat(count / 3) * 84
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
            // Preserve the box's world position across the re-parent (see endDrag.relocate).
            let worldBefore = worldCenter(of: board.nodes[idx])
            board.nodes[idx].relPath = newRel
            board.nodes[idx].center = relativeCenter(worldBefore, inDir: newDir)
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

        // Move the whole group so the centroid of its roots lands on the paste point — computed in the
        // TARGET folder's local space (the roots get stored relative to it; their subtrees follow).
        let targetOrigin = targetDir.isEmpty ? .zero
            : (board.nodes.first { $0.kind == .folder && $0.relPath == targetDir }.map { worldOrigin(of: $0) } ?? .zero)
        let centers = clipboard.map { $0.node.center }
        let anchor = CGPoint(x: centers.map(\.x).reduce(0, +) / Double(centers.count),
                             y: centers.map(\.y).reduce(0, +) / Double(centers.count))
        let cascade = isCut ? 0 : Double(pasteCount) * 24
        let delta = CGSize(width: (point.x - targetOrigin.x) - anchor.x + cascade,
                           height: (point.y - targetOrigin.y) - anchor.y + cascade)
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
        // Descendants keep their (relative-to-parent) centers — only the root is repositioned.
        for d in entry.descendants where d.relPath.hasPrefix(src.relPath + "/") {
            var dn = d
            dn.id = UUID()
            dn.relPath = newRel + String(d.relPath.dropFirst(src.relPath.count))
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
        // The subtree's boxes are stored relative to this root, so moving the root carries them along —
        // no per-descendant reposition (their relPath prefix is fixed up by reparentChildren below).
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

    /// Duplicate a selection in place as real "copy" files, reusing the disk-aware copy path that
    /// ⌘C/⌘V uses (`pasteCopyEntry` → `tCopy` duplicates each file/subtree and registers the inverse).
    /// `offset` shifts the copies off the originals (⌘D nudges; ⌥-drag duplicates with zero offset and
    /// the drag does the moving). Selects the new copies and returns their ids. One undoable transaction.
    @discardableResult
    func duplicate(_ ids: Set<UUID>, offset: CGSize = CGSize(width: 24, height: 24)) -> Set<UUID> {
        guard let vault else { return [] }
        let entries = clipboardEntries(from: ids)
        guard !entries.isEmpty else { return [] }
        func shifted(_ c: CGPoint) -> CGPoint {
            CGPoint(x: AppModel.clampCoord(c.x + offset.width), y: AppModel.clampCoord(c.y + offset.height))
        }
        var newSelection = Set<UUID>()
        transaction {
            // A duplicate is a sibling, not a re-file: each copy stays in its original's folder.
            for entry in entries {
                pasteCopyEntry(entry, into: entry.node.parentRel, vault: vault, shift: shifted, select: &newSelection)
            }
        }
        guard !newSelection.isEmpty else { return [] }
        selection = newSelection
        selectedEdge = nil
        editingId = nil
        return newSelection
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
        guard let idx = board.nodes.firstIndex(where: { $0.id == id }) else { return }
        guard (board.nodes[idx].expanded ?? false) != on else { return }
        let kind = board.nodes[idx].kind
        transaction {
            board.nodes[idx].expanded = on
            if on {
                // Open at the remembered card size (or the default), never below the current frame.
                let card = board.nodes[idx].cardSize ?? AppModel.expandedSize
                board.nodes[idx].width = max(board.nodes[idx].width, card.width)
                board.nodes[idx].height = max(board.nodes[idx].height, card.height)
            } else {
                // Remember the card size so re-expanding restores it instead of snapping to default,
                // then shrink back to the box's title-only size.
                board.nodes[idx].cardSize = CGSize(width: board.nodes[idx].width, height: board.nodes[idx].height)
                let collapsed = kind == .folder ? AppModel.folderSize : gappDefaultNoteSize
                board.nodes[idx].width = collapsed.width
                board.nodes[idx].height = collapsed.height
            }
            // A bigger card can now overlap its neighbors — push them aside (rides this same step).
            if on { resolveOverlaps(movedId: id) }
        }
    }
    func toggleExpand(_ id: UUID) {
        guard let n = node(id) else { return }
        setExpanded(id, !(n.expanded ?? false))
    }

    /// A folder's folder-note path (Obsidian convention: `<FolderName>.md` inside the folder). The
    /// file is created lazily — only on the first edit (`saveFileContent`), never just by expanding.
    func folderNoteRel(for folder: BoardNode) -> String {
        "\(folder.relPath)/\((folder.relPath as NSString).lastPathComponent).md"
    }

    /// The backing file a box's content card reads/writes: a note's own file, or a folder's folder-note.
    private func contentRel(for node: BoardNode) -> String {
        node.kind == .folder ? folderNoteRel(for: node) : node.relPath
    }

    /// Text content of a box's backing file ("" if unreadable). While time-traveling this returns the
    /// file's content at the viewed commit (from the historical cache), not the live disk text.
    func fileText(_ id: UUID) -> String {
        guard let n = node(id) else { return "" }
        let rel = contentRel(for: n)
        if isTimeTraveling { return historicalContent[rel].flatMap { $0 } ?? "" }
        guard let vault else { return "" }
        return (try? String(contentsOf: vault.url(rel), encoding: .utf8)) ?? ""
    }

    private func rawWrite(_ rel: String, _ text: String) {
        guard let vault else { return }
        markSelfWrite(rel)
        try? text.data(using: .utf8)?.write(to: vault.url(rel), options: .atomic)
    }

    /// Save edited content back to a box's file as one undoable step (no-op if unchanged). For a folder
    /// this writes its folder-note (`<FolderName>.md`), creating it lazily on this first edit — so a
    /// folder-note file never appears just from expanding a folder, only from actually editing it.
    func saveFileContent(_ id: UUID, _ text: String) {
        guard !isTimeTraveling else { return }   // history is read-only — never write a past version back
        guard let vault, let n = node(id) else { return }
        let rel = contentRel(for: n)
        let old = (try? String(contentsOf: vault.url(rel), encoding: .utf8)) ?? ""
        guard old != text else { return }
        let existed = vault.exists(rel)
        transaction {
            rawWrite(rel, text)
            txnFileRedo.append { self.rawWrite(rel, text) }
            // Undo of a first edit removes the just-created folder-note; otherwise restore old text.
            if existed { txnFileUndo.append { self.rawWrite(rel, old) } }
            else { txnFileUndo.append { _ = self.rawTrash(rel) } }
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
        // `frame` is world (from resizedFrame); store the center relative to this box's parent.
        let stored = relativeCenter(CGPoint(x: frame.midX, y: frame.midY), inDir: board.nodes[idx].parentRel)
        board.nodes[idx].center = CGPoint(x: AppModel.clampCoord(stored.x),
                                          y: AppModel.clampCoord(stored.y))
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
    /// drag's direction from the anchor, ±1 per axis). Clamps so the box never goes below `minSize`.
    /// A folder is now a viewport (folder-as-card): it resizes freely, even smaller than its
    /// contents — no contents clamp. Resizing moves only its own frame; the contents stay put.
    func resizedFrame(for node: BoardNode, anchor: CGPoint, drag rawDrag: CGPoint,
                      sign: CGVector, minSize: CGSize) -> CGRect {
        // Keep the dragged corner on its own side of the anchor (never flip past it).
        var drag = CGPoint(x: sign.dx > 0 ? max(rawDrag.x, anchor.x) : min(rawDrag.x, anchor.x),
                           y: sign.dy > 0 ? max(rawDrag.y, anchor.y) : min(rawDrag.y, anchor.y))
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

    /// Resize a box's stored frame (board.json only — never touches disk). A folder still can't render
    /// smaller than its contents (effectiveFrame clamps it), but its stored frame updates. Undoable.
    func setSize(_ id: UUID, _ size: CGSize) {
        guard let idx = board.nodes.firstIndex(where: { $0.id == id }) else { return }
        let w = max(60, min(size.width, AppModel.worldBound))
        let h = max(40, min(size.height, AppModel.worldBound))
        transaction { board.nodes[idx].width = w; board.nodes[idx].height = h }
    }

    /// Pin or unpin one or more boxes. A pinned box can't be dragged and the push solver never moves
    /// it (it's an obstacle others route around). Undoable. `pinned` is stored as nil when false so old
    /// board.json round-trips byte-compatibly.
    func setPinned(_ ids: Set<UUID>, _ on: Bool) {
        guard !ids.isEmpty else { return }
        transaction {
            for id in ids where board.nodes.contains(where: { $0.id == id }) {
                let idx = board.nodes.firstIndex { $0.id == id }!
                board.nodes[idx].pinned = on ? true : nil
            }
        }
    }
    func togglePinned(_ ids: Set<UUID>) {
        guard let first = ids.first, let n = node(first) else { return }
        setPinned(ids, !n.isPinned)
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

    /// Place `spokeIds` evenly on a circle around the hub and expand the hub — the cartographer's radial
    /// layout (docs/SPEC-mcp-cartographer.md §3). The agent says "hub H, spokes [A,B,C]"; the app owns the
    /// pixels. v1 sizes the ring so it never self-overlaps, then the existing push-on-drop solver clears any
    /// residual collision with boxes already on the board.
    /// ponytail: circle + push solver — no force-directed / crossing-minimization. Upgrade only if a
    /// radial-of-radial (sub-hubs) visibly tangles.
    func arrangeRadial(hub hubId: UUID, spokes spokeIds: [UUID]) {
        guard node(hubId) != nil, !spokeIds.isEmpty else { return }
        transaction {
            setExpanded(hubId, true)
            guard let hub = node(hubId) else { return }   // re-read: expanding can resize the card
            let center = hub.center
            let hubFrame = effectiveFrame(of: hub)
            let hubReach = max(hubFrame.width, hubFrame.height) / 2
            let spokeReach = spokeIds.compactMap { node($0) }.map { max($0.width, $0.height) / 2 }.max() ?? 0
            let gap: CGFloat = 80
            // Radius clears hub+spoke, and is wide enough that N spokes don't crowd the ring.
            let clearance = hubReach + spokeReach + gap
            let crowding = CGFloat(spokeIds.count) * (spokeReach * 2 + gap) / (2 * .pi)
            let radius = max(clearance, crowding)
            for (i, id) in spokeIds.enumerated() {
                let angle = Double(i) / Double(spokeIds.count) * 2 * .pi - .pi / 2   // first spoke at 12 o'clock
                moveSubtree(id, to: CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                                            y: center.y + radius * CGFloat(sin(angle))))
            }
            resolveOverlaps(movedId: hubId)
        }
    }

    /// Create a connector between two boxes (no duplicates, no self-loops). Undoable.
    @discardableResult
    func connect(from: UUID, to: UUID) -> Bool {
        guard from != to,
              node(from) != nil, node(to) != nil,
              !board.edges.contains(where: { ($0.from == from && $0.to == to) ||
                                             ($0.from == to && $0.to == from) }) else { return false }
        transaction {
            let a = node(from), b = node(to)
            let real = a.map { isLinkable($0) } == true && b.map { isLinkable($0) } == true
            let edge = BoardEdge(from: from, to: to, linkBacked: real ? true : nil)
            board.edges.append(edge)
            if let a, let b { writeLink(from: a, to: b) }
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

    /// Re-anchor an existing connector to a new pair of boxes (dragging an endpoint onto another box).
    /// If the old edge was a real `[[wikilink]]`, the link follows: the old directional link is removed
    /// and the new one written via the same managed-block machinery — one undo step covers both files
    /// and the board. No-op for a self-loop, an unchanged route, or a route that would duplicate another
    /// edge. Link writes are no-ops for non-linkable endpoints, so such a re-route stays visual-only.
    @discardableResult
    func rerouteEdge(_ id: UUID, newFrom: UUID, newTo: UUID) -> Bool {
        guard let idx = board.edges.firstIndex(where: { $0.id == id }),
              newFrom != newTo, node(newFrom) != nil, node(newTo) != nil else { return false }
        let old = board.edges[idx]
        guard old.from != newFrom || old.to != newTo else { return false }
        let duplicatesOther = board.edges.contains { other in
            other.id != id && ((other.from == newFrom && other.to == newTo) ||
                               (other.from == newTo && other.to == newFrom))
        }
        guard !duplicatesOther else { return false }
        transaction {
            if let a = node(old.from), let b = node(old.to) { removeLink(from: a, to: b) }
            board.edges[idx].from = newFrom
            board.edges[idx].to = newTo
            if let a = node(newFrom), let b = node(newTo) {
                writeLink(from: a, to: b)
                board.edges[idx].linkBacked = (isLinkable(a) && isLinkable(b)) ? true : nil
            }
        }
        return true
    }

    private func mutateEdge(_ id: UUID, _ change: (inout BoardEdge) -> Void) {
        guard let idx = board.edges.firstIndex(where: { $0.id == id }) else { return }
        transaction { change(&board.edges[idx]) }
    }

    func setEdgeColor(_ id: UUID, _ color: BoxColor?) { mutateEdge(id) { $0.colorName = color?.rawValue } }
    func setEdgeStyle(_ id: UUID, _ style: EdgeStyle) { mutateEdge(id) { $0.styleRaw = style.rawValue } }
    func setEdgeDirected(_ id: UUID, _ on: Bool) { mutateEdge(id) { $0.directed = on } }

    /// Set (or clear, when empty/blank) a connector's label. Trimmed; blank → nil so an empty label
    /// never persists or renders.
    func setEdgeLabel(_ id: UUID, _ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateEdge(id) { $0.label = trimmed.isEmpty ? nil : trimmed }
    }

    // MARK: Navigation

    func center(on id: UUID) {
        guard let n = node(id) else { return }
        selection = [id]
        selectedEdge = nil
        guard viewport != .zero else { return }
        let c = worldCenter(of: n)
        pan = CGSize(width: viewport.width / 2 - c.x * zoom,
                     height: viewport.height / 2 - c.y * zoom)
    }

    /// Center the view on existing content (or world center) the first time we have a size.
    func initViewIfNeeded() {
        guard !didInitView, viewport != .zero else { return }
        didInitView = true
        recenterOnContent()
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
