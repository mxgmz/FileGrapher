import SwiftUI
import AppKit

let gappSpring = Animation.spring(response: 0.30, dampingFraction: 0.78)

struct CanvasView: View {
    @EnvironmentObject var model: AppModel

    // marquee (rubber-band) selection state, in canvas-local screen coords
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var marqueeBase: Set<UUID> = []   // selection to add to (Shift-drag)
    // input monitor (scroll / pinch / delete key)
    @State private var monitor: Any?

    private var folders: [BoardNode] { model.board.nodes.filter { $0.kind == .folder } }
    private var notes: [BoardNode] { model.board.nodes.filter { $0.kind == .note } }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                grid.allowsHitTesting(false)
                interactiveEdges
                world
                historyGhostLayer
                dropTargetOutline
                pendingConnector
                handles
                marqueeOverlay
                FilePeekOverlay()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .bottom) { CommitScrubber() }
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear {
                            model.viewport = geo.size
                            model.canvasFrameGlobal = g.frame(in: .global)
                            model.initViewIfNeeded()
                        }
                        .onChange(of: g.frame(in: .global)) { _, f in
                            // Epsilon guard: writing this back into @Published state can feed
                            // relayout. Ignore sub-pixel jitter so we never oscillate into a
                            // redraw loop that pins WindowServer.
                            let prev = model.canvasFrameGlobal
                            if abs(prev.origin.x - f.origin.x) > 0.5 || abs(prev.origin.y - f.origin.y) > 0.5
                                || abs(prev.width - f.width) > 0.5 || abs(prev.height - f.height) > 0.5 {
                                model.canvasFrameGlobal = f
                            }
                        }
                }
            )
            .onChange(of: geo.size) { _, s in
                model.viewport = s
                model.initViewIfNeeded()
            }
            .onAppear { installMonitor() }
            .onDisappear { removeMonitor() }
            .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in
                withAnimation(gappSpring) { _ = model.addNote(inDir: "", at: viewportCenterWorld()) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .newFolder)) { _ in
                withAnimation(gappSpring) { _ = model.addFolder(inDir: "", at: viewportCenterWorld()) }
            }
        }
    }

    private func viewportCenterWorld() -> CGPoint {
        model.screenToWorld(CGPoint(x: model.viewport.width / 2, y: model.viewport.height / 2))
    }

    // MARK: Background + gestures

    private var background: some View {
        Rectangle()
            .fill(Color(nsColor: .textBackgroundColor))
            .contentShape(Rectangle())
            .gesture(marqueeGesture)
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { v in
                        withAnimation(gappSpring) { _ = model.addNote(inDir: "", at: model.screenToWorld(v.location)) }
                    }
                    .exclusively(before:
                        SpatialTapGesture(count: 1).onEnded { _ in
                            model.selection = []
                            model.editingId = nil
                            model.selectedEdge = nil
                        }
                    )
            )
            .contextMenu { backgroundMenu }
    }

    /// Right-click on empty canvas: create / paste / select-all. (Box and connector menus live on
    /// `NodeView`/`EdgeLine`.) New Note lands at the cursor's world point, matching double-click.
    @ViewBuilder
    private var backgroundMenu: some View {
        Button("New Note") {
            withAnimation(gappSpring) { _ = model.addNote(inDir: "", at: pastePoint()) }
        }
        if model.canPaste {
            Button("Paste") { withAnimation(gappSpring) { model.paste(at: pastePoint()) } }
        }
        if !model.board.nodes.isEmpty {
            Button("Select All") {
                model.selection = Set(model.board.nodes.map { $0.id })
                model.selectedEdge = nil
            }
        }
    }

    /// Drag on the empty canvas to rubber-band a selection (Shift adds to the current selection).
    /// Panning is via two-finger scroll / pinch (the input monitor), which is unaffected.
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { v in
                if marqueeStart == nil {
                    marqueeStart = v.startLocation
                    marqueeBase = NSEvent.modifierFlags.contains(.shift) ? model.selection : []
                    model.editingId = nil
                    model.selectedEdge = nil
                }
                marqueeCurrent = v.location
                applyMarqueeSelection()
            }
            .onEnded { _ in
                marqueeStart = nil
                marqueeCurrent = nil
                marqueeBase = []
            }
    }

    /// Screen-space rect of the in-progress marquee (nil when not dragging).
    private var marqueeRect: CGRect? {
        guard let s = marqueeStart, let c = marqueeCurrent else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(c.x - s.x), height: abs(c.y - s.y))
    }

    private func applyMarqueeSelection() {
        guard let r = marqueeRect else { return }
        let tl = model.screenToWorld(CGPoint(x: r.minX, y: r.minY))
        let br = model.screenToWorld(CGPoint(x: r.maxX, y: r.maxY))
        let world = CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
        var hit = marqueeBase
        for n in model.board.nodes where model.effectiveFrame(of: n).intersects(world) {
            hit.insert(n.id)
        }
        model.selection = hit
    }

    @ViewBuilder
    private var marqueeOverlay: some View {
        if let r = marqueeRect {
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .overlay(Rectangle().stroke(Color.accentColor.opacity(0.7), lineWidth: 1))
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .allowsHitTesting(false)
        }
    }

    // MARK: Trackpad / mouse input monitor

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .keyDown]) { event in
            handle(event)
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown { return handleKey(event) }

        guard let win = event.window, win.isKeyWindow else { return event }
        let frame = model.canvasFrameGlobal
        guard frame != .zero else { return event }
        let winH = win.contentView?.bounds.height ?? win.frame.height
        let topLeft = CGPoint(x: event.locationInWindow.x, y: winH - event.locationInWindow.y)
        guard frame.contains(topLeft) else { return event }
        let local = CGPoint(x: topLeft.x - frame.minX, y: topLeft.y - frame.minY)

        switch event.type {
        case .scrollWheel:
            // Decide whether this scroll pans the canvas or scrolls a card/peek. To keep a free pan
            // from being hijacked when the cursor sweeps across a card mid-swipe, we LOCK the decision
            // at the start of a continuous trackpad gesture and hold it until the gesture ends.
            let w = model.screenToWorld(local)
            let overCardNow = model.peekId != nil
                || model.board.nodes.contains { $0.isExpanded && model.effectiveFrame(of: $0).contains(w) }
            let isGesture = !event.phase.isEmpty || !event.momentumPhase.isEmpty
            if event.phase.contains(.began) { model.scrollOverCard = overCardNow }
            // Trackpad gesture (incl. its momentum) follows the lock; a legacy wheel hit-tests live.
            let routeToCard = isGesture ? (model.scrollOverCard ?? overCardNow) : overCardNow
            if event.momentumPhase.contains(.ended) || event.phase.contains(.cancelled) {
                model.scrollOverCard = nil
            }
            if routeToCard { return event }   // let the card / peek scroll natively
            if event.modifierFlags.contains(.command) {
                model.zoomToward(local, factor: 1 - event.scrollingDeltaY * 0.0025)
            } else {
                let mult: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
                model.pan.width += event.scrollingDeltaX * mult
                model.pan.height += event.scrollingDeltaY * mult
            }
            return nil
        case .magnify:
            model.zoomToward(local, factor: 1 + event.magnification)
            return nil
        default:
            return event
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // Esc = global escape hatch (but not during inline title rename, which uses Esc to cancel):
        // exit a card editor, else close the peek, else collapse the selected card.
        if event.keyCode == 53, model.editingId == nil {
            if NSApp.keyWindow?.firstResponder is NSText {
                NSApp.keyWindow?.makeFirstResponder(nil); return nil
            }
            if model.peekId != nil {
                withAnimation(gappSpring) { model.closePeek() }; return nil
            }
            if model.selection.count == 1, let id = model.selection.first,
               model.node(id)?.isExpanded == true {
                withAnimation(gappSpring) { model.setExpanded(id, false) }; return nil
            }
        }

        // Never steal keys while renaming or while a text field is first responder
        // (so ⌘C/⌘X/⌘V keep working natively inside the rename / card editor field).
        if model.editingId != nil { return event }
        if NSApp.keyWindow?.firstResponder is NSText { return event }

        // ⌘C / ⌘X / ⌘V — box clipboard.
        if event.modifierFlags.contains(.command),
           let ch = event.charactersIgnoringModifiers?.lowercased() {
            switch ch {
            case "c" where !model.selection.isEmpty:
                model.copyToClipboard(); return nil
            case "x" where !model.selection.isEmpty:
                model.cutToClipboard(); return nil
            case "v" where model.canPaste:
                withAnimation(gappSpring) { model.paste(at: pastePoint()) }; return nil
            case "a" where !model.board.nodes.isEmpty:
                model.selection = Set(model.board.nodes.map { $0.id })
                model.selectedEdge = nil
                return nil
            default: break
            }
        }

        // Space = Quick Look the selected box's content (Esc closes it — handled above).
        if event.keyCode == 49, model.selection.count == 1, let id = model.selection.first {
            withAnimation(gappSpring) { model.togglePeek(id) }
            return nil
        }

        // 51 = delete/backspace, 117 = forward delete
        if event.keyCode == 51 || event.keyCode == 117 {
            if let e = model.selectedEdge {
                model.deleteEdge(e)
                return nil
            }
            if !model.selection.isEmpty {
                withAnimation(gappSpring) { model.delete(model.selection) }
                return nil
            }
        }
        return event
    }

    /// Where ⌘V should drop: the cursor in world space if it's over the canvas, else the viewport center.
    private func pastePoint() -> CGPoint {
        if let w = cursorWorld() { return w }
        return model.screenToWorld(CGPoint(x: model.viewport.width / 2, y: model.viewport.height / 2))
    }

    private func cursorWorld() -> CGPoint? {
        guard let win = NSApp.keyWindow else { return nil }
        let winPt = win.convertPoint(fromScreen: NSEvent.mouseLocation)
        let winH = win.contentView?.bounds.height ?? win.frame.height
        let topLeft = CGPoint(x: winPt.x, y: winH - winPt.y)
        let frame = model.canvasFrameGlobal
        guard frame != .zero, frame.contains(topLeft) else { return nil }
        return model.screenToWorld(CGPoint(x: topLeft.x - frame.minX, y: topLeft.y - frame.minY))
    }

    // MARK: Grid

    private var grid: some View {
        Canvas { ctx, size in
            let spacing = AppModel.gridStep * model.zoom
            guard spacing > 9 else { return }
            let startX = model.pan.width.truncatingRemainder(dividingBy: spacing)
            let startY = model.pan.height.truncatingRemainder(dividingBy: spacing)
            let dot = Path(ellipseIn: CGRect(x: -1.1, y: -1.1, width: 2.2, height: 2.2))
            var y = startY
            while y < size.height {
                var x = startX
                while x < size.width {
                    ctx.fill(dot.offsetBy(dx: x, dy: y), with: .color(.gray.opacity(0.28)))
                    x += spacing
                }
                y += spacing
            }
        }
    }

    // MARK: Edges

    /// A node's displayed (auto-grown) frame in screen space.
    private func screenRect(_ node: BoardNode) -> CGRect {
        let f = model.effectiveFrame(of: node)
        let c = model.worldToScreen(CGPoint(x: f.midX, y: f.midY))
        let w = f.width * model.zoom, h = f.height * model.zoom
        return CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    }

    /// Curve control points for an edge, edge-to-edge in screen space.
    /// Returns (start, control1, control2, end).
    private func edgeGeometry(_ edge: BoardEdge) -> (CGPoint, CGPoint, CGPoint, CGPoint)? {
        guard let a = model.node(edge.from), let b = model.node(edge.to) else { return nil }
        let ra = screenRect(a), rb = screenRect(b)
        let dx = rb.midX - ra.midX, dy = rb.midY - ra.midY
        let p1, p2, c1, c2: CGPoint
        if abs(dx) >= abs(dy) {
            // exit/enter on left/right edges -> horizontal S-curve
            let s: CGFloat = dx >= 0 ? 1 : -1
            p1 = CGPoint(x: dx >= 0 ? ra.maxX : ra.minX, y: ra.midY)
            p2 = CGPoint(x: dx >= 0 ? rb.minX : rb.maxX, y: rb.midY)
            let off = max(36, abs(p2.x - p1.x) * 0.5)
            c1 = CGPoint(x: p1.x + off * s, y: p1.y)
            c2 = CGPoint(x: p2.x - off * s, y: p2.y)
        } else {
            // exit/enter on top/bottom edges -> vertical S-curve
            let s: CGFloat = dy >= 0 ? 1 : -1
            p1 = CGPoint(x: ra.midX, y: dy >= 0 ? ra.maxY : ra.minY)
            p2 = CGPoint(x: rb.midX, y: dy >= 0 ? rb.minY : rb.maxY)
            let off = max(36, abs(p2.y - p1.y) * 0.5)
            c1 = CGPoint(x: p1.x, y: p1.y + off * s)
            c2 = CGPoint(x: p2.x, y: p2.y - off * s)
        }
        return (p1, c1, c2, p2)
    }

    /// One hit-testable, selectable view per connector (taps select, right-click restyles/deletes).
    private var interactiveEdges: some View {
        ZStack {
            ForEach(model.board.edges) { edge in
                if let g = edgeGeometry(edge) {
                    EdgeLine(edge: edge, p1: g.0, c1: g.1, c2: g.2, p2: g.3,
                             selected: model.selectedEdge == edge.id,
                             absentInHistory: model.isEdgeAbsentInHistory(edge.id))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: World — folders first so notes render above them

    // Shallower folders first so a nested folder renders on top of its parent.
    private var sortedFolders: [BoardNode] {
        folders.sorted {
            $0.relPath.components(separatedBy: "/").count < $1.relPath.components(separatedBy: "/").count
        }
    }

    private var world: some View {
        ZStack(alignment: .topLeading) {
            ForEach(sortedFolders) { node in placed(node) }
            ForEach(notes) { node in placed(node) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Deleted-since ghosts (files present at the viewed commit, gone now). Render-only, never hit-tested.
    @ViewBuilder
    private var historyGhostLayer: some View {
        if model.isTimeTraveling {
            // Ghost connectors first, so a ghost box draws over its own dangling endpoints.
            ForEach(model.historyGhostEdges) { ghost in
                if let g = edgeGeometry(BoardEdge(from: ghost.from, to: ghost.to)) {
                    GhostEdgeLine(p1: g.0, c1: g.1, c2: g.2, p2: g.3).transition(.opacity)
                }
            }
            ForEach(model.historyGhosts) { ghost in
                HistoryGhostBox(ghost: ghost)
                    .position(model.worldToScreen(ghost.center))
                    .transition(.opacity)
            }
        }
    }

    private func placed(_ node: BoardNode) -> some View {
        let f = model.effectiveFrame(of: node)
        // No .scaleEffect: NodeView renders itself in screen space (every dimension × zoom) so
        // text stays crisp vector glyphs at any zoom / font size instead of an upscaled bitmap.
        return NodeView(node: node, displayFrame: f)
            .position(model.worldToScreen(CGPoint(x: f.midX, y: f.midY)))
            .transition(.scale(scale: 0.7).combined(with: .opacity))
    }

    // MARK: In-progress connector (dragging out of a handle)

    @ViewBuilder
    private var pendingConnector: some View {
        if let pc = model.pendingConnect, let src = model.node(pc.from) {
            let f = model.effectiveFrame(of: src)
            let start = model.worldToScreen(CGPoint(x: f.midX, y: f.midY))
            ZStack {
                Path { p in
                    p.move(to: start)
                    p.addLine(to: pc.toPoint)
                }
                .stroke(Color.accentColor.opacity(0.85),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 4]))
                if let t = pc.hoverTarget, let tn = model.node(t) {
                    let tf = model.effectiveFrame(of: tn)
                    let c = model.worldToScreen(CGPoint(x: tf.midX, y: tf.midY))
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: tf.width * model.zoom, height: tf.height * model.zoom)
                        .position(c)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Live outline of the folder a dragged box will re-file into (set during a single-box drag).
    @ViewBuilder
    private var dropTargetOutline: some View {
        if let id = model.dropTargetId, let folder = model.node(id) {
            let f = model.effectiveFrame(of: folder)
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [7, 4]))
                .frame(width: f.width * model.zoom, height: f.height * model.zoom)
                .position(model.worldToScreen(CGPoint(x: f.midX, y: f.midY)))
                .allowsHitTesting(false)
        }
    }

    // MARK: Spawn handles for the single selected box

    @ViewBuilder
    private var handles: some View {
        if model.selection.count == 1,
           let id = model.selection.first,
           let node = model.node(id),
           model.editingId != id {
            let f = model.effectiveFrame(of: node)
            let center = model.worldToScreen(CGPoint(x: f.midX, y: f.midY))
            let halfW = f.width / 2 * model.zoom
            let halfH = f.height / 2 * model.zoom
            let off: CGFloat = 18
            HandleButton(direction: .up, node: node).position(x: center.x, y: center.y - halfH - off)
            HandleButton(direction: .down, node: node).position(x: center.x, y: center.y + halfH + off)
            HandleButton(direction: .left, node: node).position(x: center.x - halfW - off, y: center.y)
            HandleButton(direction: .right, node: node).position(x: center.x + halfW + off, y: center.y)

            // Corner resize handles (notes and folders alike).
            ResizeHandle(node: node, corner: .topLeft)
                .position(model.worldToScreen(CGPoint(x: f.minX, y: f.minY)))
            ResizeHandle(node: node, corner: .topRight)
                .position(model.worldToScreen(CGPoint(x: f.maxX, y: f.minY)))
            ResizeHandle(node: node, corner: .bottomLeft)
                .position(model.worldToScreen(CGPoint(x: f.minX, y: f.maxY)))
            ResizeHandle(node: node, corner: .bottomRight)
                .position(model.worldToScreen(CGPoint(x: f.maxX, y: f.maxY)))
        }
    }
}

// MARK: - Handle button

struct HandleButton: View {
    @EnvironmentObject var model: AppModel
    let direction: Direction
    let node: BoardNode
    @State private var hover = false

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.accentColor))
            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .scaleEffect(hover ? 1.14 : 1)
            .contentShape(Circle())
            .onHover { hover = $0 }
            .onTapGesture {
                withAnimation(gappSpring) { model.spawn(from: node, direction: direction) }
            }
            .gesture(connectDrag)
            .help(node.kind == .folder
                  ? "Click: add connected folder · Drag: connect to another box"
                  : "Click: add connected note · Drag: connect to another box")
    }

    /// Drag from the handle to draw a connector onto another box.
    private var connectDrag: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in
                let local = model.canvasLocal(v.location)
                let target = model.node(atWorld: model.screenToWorld(local))
                model.pendingConnect = PendingConnect(
                    from: node.id,
                    toPoint: local,
                    hoverTarget: (target.map { $0.id != node.id ? $0.id : nil }) ?? nil)
            }
            .onEnded { v in
                let target = model.node(atWorld: model.screenToWorld(model.canvasLocal(v.location)))
                if let target, target.id != node.id {
                    withAnimation(gappSpring) { _ = model.connect(from: node.id, to: target.id) }
                }
                model.pendingConnect = nil
            }
    }
}

// MARK: - Connector line (selectable / editable)

/// Filled triangle arrowhead pointing at `tip`, oriented along `tip - from`.
func gappArrowhead(tip: CGPoint, from: CGPoint) -> Path {
    let angle = atan2(tip.y - from.y, tip.x - from.x)
    let len: CGFloat = 9, spread = CGFloat.pi / 7
    var p = Path()
    p.move(to: tip)
    p.addLine(to: CGPoint(x: tip.x - len * cos(angle - spread), y: tip.y - len * sin(angle - spread)))
    p.addLine(to: CGPoint(x: tip.x - len * cos(angle + spread), y: tip.y - len * sin(angle + spread)))
    p.closeSubpath()
    return p
}

/// A faded, dashed placeholder for a file that existed at the viewed commit but is gone now. Render-only
/// (no select/drag/hit-testing) — it just shows "this used to be here" while time-traveling.
private struct HistoryGhostBox: View {
    @EnvironmentObject var model: AppModel
    let ghost: HistoryGhost
    private var scale: CGFloat { model.zoom }

    var body: some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: "clock.badge.xmark").font(.system(size: 12 * scale))
            Text(ghost.name).font(.system(size: 13 * scale, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 10 * scale)
        .frame(width: ghost.size.width * scale, height: ghost.size.height * scale, alignment: .leading)
        .foregroundStyle(.secondary)
        .background(RoundedRectangle(cornerRadius: 10 * scale)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10 * scale)
            .stroke(style: StrokeStyle(lineWidth: 1.5 * scale, dash: [5 * scale, 4 * scale]))
            .foregroundStyle(.secondary.opacity(0.6)))
        .opacity(0.6)
        .allowsHitTesting(false)
    }
}

/// A faded, dashed ghost connector for a `[[link]]` that existed at the viewed commit but isn't drawn now.
/// Render-only, never hit-tested — the connector counterpart to `HistoryGhostBox`.
private struct GhostEdgeLine: View {
    let p1, c1, c2, p2: CGPoint
    private var path: Path {
        var p = Path(); p.move(to: p1); p.addCurve(to: p2, control1: c1, control2: c2); return p
    }
    var body: some View {
        ZStack {
            path.stroke(Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
            gappArrowhead(tip: p2, from: c2).fill(Color.secondary.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

struct EdgeLine: View {
    @EnvironmentObject var model: AppModel
    let edge: BoardEdge
    let p1: CGPoint
    let c1: CGPoint
    let c2: CGPoint
    let p2: CGPoint
    let selected: Bool
    var absentInHistory = false   // link not in the viewed commit → dim + dash ("added later")

    @State private var hovering = false
    @State private var dragEnd: EdgeEnd?        // which endpoint is being dragged (nil == none)
    @State private var dragPoint: CGPoint?      // the endpoint's live screen position while dragging
    @State private var dropTarget: UUID?        // box the dragged endpoint would re-route onto
    @State private var editingLabel = false
    @State private var labelDraft = ""
    @FocusState private var labelFocused: Bool

    private enum EdgeEnd { case from, to }

    private var linePath: Path {
        var p = Path()
        p.move(to: p1)
        if edge.style == .straight {
            p.addLine(to: p2)
        } else {
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }

    private var arrowPath: Path {
        gappArrowhead(tip: p2, from: edge.style == .straight ? p1 : c2)
    }

    /// Approximate point on the curve at t=0.5 (cubic-Bezier midpoint), where a label reads cleanly.
    private var midPoint: CGPoint {
        if edge.style == .straight { return CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2) }
        return CGPoint(x: 0.125 * p1.x + 0.375 * c1.x + 0.375 * c2.x + 0.125 * p2.x,
                       y: 0.125 * p1.y + 0.375 * c1.y + 0.375 * c2.y + 0.125 * p2.y)
    }

    var body: some View {
        ZStack {
            if selected {
                linePath.stroke(edge.color.opacity(0.28),
                                style: StrokeStyle(lineWidth: 9, lineCap: .round))
            } else if hovering {
                // Surface the (otherwise invisible) hit zone so the user sees what a click will grab.
                linePath.stroke(edge.color.opacity(0.18),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round))
            }
            linePath.stroke(edge.color.opacity(absentInHistory ? 0.3 : 1),
                            style: StrokeStyle(lineWidth: selected ? 3 : 2, lineCap: .round,
                                               dash: absentInHistory ? [6, 4] : []))
            if edge.isDirected { arrowPath.fill(edge.color.opacity(absentInHistory ? 0.3 : 1)) }
            label
            if selected && !model.isTimeTraveling { endpointHandles }
            rerouteOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Hit area is only the fattened line, so taps off the line fall through to the canvas.
        .contentShape(linePath.strokedPath(StrokeStyle(lineWidth: 18, lineCap: .round)))
        .onHover { hovering = $0 }
        .onTapGesture { model.selectEdge(edge.id) }
        .contextMenu { contextMenu }
    }

    // MARK: Draggable endpoints (re-route)

    @ViewBuilder
    private var endpointHandles: some View {
        // Nudge each handle just off the box edge (toward its control point / the other end) so it sits
        // in open canvas — the edge layer draws *below* the boxes, so a handle over a box would be hidden.
        endpointHandle(.from, at: nudged(p1, toward: edge.style == .straight ? p2 : c1))
        endpointHandle(.to, at: nudged(p2, toward: edge.style == .straight ? p1 : c2))
    }

    private func nudged(_ point: CGPoint, toward other: CGPoint) -> CGPoint {
        let dx = other.x - point.x, dy = other.y - point.y
        let len = max(1, hypot(dx, dy))
        let step: CGFloat = 9
        return CGPoint(x: point.x + dx / len * step, y: point.y + dy / len * step)
    }

    private func endpointHandle(_ end: EdgeEnd, at anchor: CGPoint) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(edge.color.opacity(0.9), lineWidth: 2))
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .frame(width: 12, height: 12)
            .position(dragEnd == end ? (dragPoint ?? anchor) : anchor)
            .gesture(rerouteDrag(end))
            .help("Drag onto another box to re-route this connection")
    }

    private func rerouteDrag(_ end: EdgeEnd) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { v in
                let local = model.canvasLocal(v.location)
                dragEnd = end
                dragPoint = local
                let target = model.node(atWorld: model.screenToWorld(local))
                let fixedEnd = end == .from ? edge.to : edge.from
                dropTarget = (target?.id != fixedEnd) ? target?.id : nil
            }
            .onEnded { v in
                let target = model.node(atWorld: model.screenToWorld(model.canvasLocal(v.location)))
                if let target {
                    let newFrom = end == .from ? target.id : edge.from
                    let newTo = end == .to ? target.id : edge.to
                    withAnimation(gappSpring) { _ = model.rerouteEdge(edge.id, newFrom: newFrom, newTo: newTo) }
                }
                dragEnd = nil; dragPoint = nil; dropTarget = nil
            }
    }

    /// While dragging an endpoint: a dashed lead to the cursor and a highlight on the box it'd land on.
    @ViewBuilder
    private var rerouteOverlay: some View {
        if let dragEnd, let dragPoint {
            let anchor = dragEnd == .from ? p2 : p1
            Path { p in p.move(to: anchor); p.addLine(to: dragPoint) }
                .stroke(edge.color.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                .allowsHitTesting(false)
            if let dropTarget, let targetNode = model.node(dropTarget) {
                let f = model.effectiveFrame(of: targetNode)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(edge.color, lineWidth: 3)
                    .frame(width: f.width * model.zoom, height: f.height * model.zoom)
                    .position(model.worldToScreen(CGPoint(x: f.midX, y: f.midY)))
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Label

    @ViewBuilder
    private var label: some View {
        if editingLabel {
            TextField("Label", text: $labelDraft)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 110)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(edge.color.opacity(0.6), lineWidth: 1))
                .focused($labelFocused)
                .onAppear { labelDraft = edge.label ?? ""; labelFocused = true }
                .onSubmit { commitLabel() }
                .onExitCommand { editingLabel = false }
                .onChange(of: labelFocused) { _, focused in if !focused { commitLabel() } }
                .position(midPoint)
        } else if let text = edge.label, !text.isEmpty {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(edge.color.opacity(0.4), lineWidth: 1))
                .onTapGesture { model.selectEdge(edge.id); editingLabel = true }
                .position(midPoint)
        }
    }

    private func commitLabel() {
        model.setEdgeLabel(edge.id, labelDraft)
        editingLabel = false
    }

    @ViewBuilder
    private var contextMenu: some View {
        Menu("Color") {
            Button("Default") { model.setEdgeColor(edge.id, nil) }
            Divider()
            ForEach(BoxColor.allCases) { c in
                Button(c.label) { model.setEdgeColor(edge.id, c) }
            }
        }
        Menu("Style") {
            ForEach(EdgeStyle.allCases) { s in
                Button {
                    model.setEdgeStyle(edge.id, s)
                } label: {
                    if edge.style == s { Label(s.label, systemImage: "checkmark") }
                    else { Text(s.label) }
                }
            }
        }
        Button(edge.isDirected ? "Hide Arrowhead" : "Show Arrowhead") {
            model.setEdgeDirected(edge.id, !edge.isDirected)
        }
        Button(edge.label == nil ? "Add Label…" : "Edit Label…") {
            model.selectEdge(edge.id); editingLabel = true
        }
        if edge.label != nil {
            Button("Remove Label") { model.setEdgeLabel(edge.id, "") }
        }
        Divider()
        Button("Delete Connection", role: .destructive) { model.deleteEdge(edge.id) }
    }
}

// MARK: - Node (box) view

struct NodeView: View {
    @EnvironmentObject var model: AppModel
    let node: BoardNode
    let displayFrame: CGRect
    @State private var groupStart: [UUID: CGPoint] = [:]   // start centers of every box moving with this drag
    @State private var groupMultiSelect = false            // true == dragging a multi-selection (skip re-file)
    @State private var dragIds: Set<UUID> = []             // boxes this drag moves (the duplicates on ⌥-drag)
    @State private var dragRootId: UUID?                   // the dragged box (a duplicate's id on ⌥-drag)
    @State private var hovering = false
    @State private var cardText = ""        // expanded-card content (loaded lazily)
    @State private var cardDraft = ""       // expanded-card editor buffer
    @State private var cardEditing = false

    private let headerHeight: CGFloat = 40
    /// Render scale = current zoom. Every fixed dimension below is multiplied by this so the box is
    /// drawn at its final pixel size with native (crisp) text, rather than an upscaled bitmap.
    private var scale: CGFloat { model.zoom }
    private var isSelected: Bool { model.selection.contains(node.id) }
    private var isEditing: Bool { model.editingId == node.id }
    /// While time-traveling, this box's file didn't exist yet at the viewed commit (added-later).
    private var isHistoryGhost: Bool { model.isAbsentInHistory(node.id) }

    var body: some View {
        // When expanded, the box's own drag/tap are masked to subviews so the card body can
        // scroll/select/edit and only the header drags the box.
        let mask: GestureMask = node.isExpanded ? .subviews : .all
        content
            .frame(width: displayFrame.width * scale, height: displayFrame.height * scale)
            .opacity(model.cutIds.contains(node.id) ? 0.45 : (isHistoryGhost ? 0.3 : 1))   // cut source / added-later ghost
            .overlay {   // added-later: a dashed outline marks "not in this version yet"
                if isHistoryGhost {
                    RoundedRectangle(cornerRadius: 10 * scale)
                        .stroke(style: StrokeStyle(lineWidth: 1.5 * scale, dash: [5 * scale, 4 * scale]))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }
            .overlay(alignment: .topTrailing) { if node.kind == .note && !node.isExpanded { expandChevron } }
            .contentShape(Rectangle())
            .gesture(dragGesture, including: mask)
            .gesture(
                SpatialTapGesture(count: 2, coordinateSpace: .local)
                    .onEnded { v in handleDoubleTap(at: v.location) }
                    .exclusively(before:
                        SpatialTapGesture(count: 1).onEnded { _ in select() }
                    ),
                including: mask
            )
            .contextMenu { menu }
            .onHover { hovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: isSelected)
            .animation(.easeInOut(duration: 0.12), value: hovering)
    }

    /// Hover affordance: a small button that expands the note into an in-place content card.
    private var expandChevron: some View {
        Button { withAnimation(gappSpring) { model.toggleExpand(node.id) } } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9 * scale, weight: .bold))
                .foregroundStyle(node.accent)
                .padding(5 * scale)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(node.accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0)
        .padding(6 * scale)
        .help("Expand into a card")
    }

    @ViewBuilder
    private var content: some View {
        if node.kind == .folder { folderBox }
        else if node.isExpanded { expandedCard }
        else { noteBox }
    }

    // MARK: Expanded in-place content card

    private var expandedCard: some View {
        VStack(spacing: 0) {
            cardHeader
            if model.hasDiskConflict(node.id) { conflictBanner }
            Divider()
            cardBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12 * scale).fill(Color(nsColor: .controlBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: 12 * scale))
        .overlay(
            RoundedRectangle(cornerRadius: 12 * scale)
                .stroke(noteBorderColor, lineWidth: (isSelected ? 2.5 : (hasCustomColor ? 1.5 : 1)) * scale)
        )
        .shadow(color: .black.opacity(0.12), radius: (isSelected ? 7 : 4) * scale, y: 2 * scale)
        .onAppear { cardText = model.fileText(node.id); cardDraft = cardText }
        .onChange(of: model.diskRevision) { _, _ in
            // A watched file changed (our own link-write or an external edit). Re-read — but never
            // while the user is editing this card, or we'd clobber their unsaved draft. An external
            // change to an in-edit card instead raises model.diskConflicts → the reload banner below.
            guard !cardEditing else { return }
            let fresh = model.fileText(node.id)
            if fresh != cardText { cardText = fresh; cardDraft = fresh }
        }
        .onChange(of: model.viewedCommit) { _, _ in
            // Entering/leaving time-travel: history is read-only, so drop any edit and show this
            // commit's content (the diskRevision reload above is skipped while editing).
            if cardEditing { model.endEditingFile(node.id) }
            cardEditing = false
            cardText = model.fileText(node.id); cardDraft = cardText
        }
        .onDisappear { if cardEditing { model.saveFileContent(node.id, cardDraft); model.endEditingFile(node.id) } }
    }

    /// Sober reload prompt: an external edit landed on this file while you were editing its card.
    /// Reload discards the local draft and re-reads disk; dismiss keeps editing (next save wins).
    private var conflictBanner: some View {
        HStack(spacing: 8 * scale) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11 * scale))
            Text("Updated on disk").font(.system(size: 12 * scale, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4 * scale)
            Button("Reload") { reloadFromDisk() }
                .buttonStyle(.plain).font(.system(size: 11 * scale, weight: .semibold))
            Button { model.clearDiskConflict(node.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).font(.system(size: 10 * scale))
                .help("Keep editing")
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 10 * scale)
        .frame(height: 26 * scale)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.14))
    }

    private var cardHeader: some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: noteIconName).foregroundStyle(node.accent).font(.system(size: 13 * scale))
            title.font(.system(size: 13 * scale, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4 * scale)
            if model.isTimeTraveling {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11 * scale)).foregroundStyle(.orange)
                    .help("Viewing history — read-only")
            } else if node.fileType == .markdown {
                Button { toggleCardEdit() } label: {
                    Image(systemName: cardEditing ? "eye" : "square.and.pencil").font(.system(size: 11 * scale))
                }
                .buttonStyle(.plain).help(cardEditing ? "Preview" : "Edit")
            }
            Button { withAnimation(gappSpring) { model.setExpanded(node.id, false) } } label: {
                Image(systemName: "chevron.up").font(.system(size: 11 * scale, weight: .bold))
            }
            .buttonStyle(.plain).help("Collapse")
        }
        .padding(.horizontal, 10 * scale)
        .frame(height: 30 * scale)
        .frame(maxWidth: .infinity)
        .background(node.accent.opacity(0.12))
        .contentShape(Rectangle())
        .gesture(dragGesture)              // header is the drag handle
        .onTapGesture { select() }
    }

    @ViewBuilder
    private var cardBody: some View {
        Group {
            if model.isAbsentInHistory(node.id) {
                VStack(spacing: 6 * scale) {
                    Image(systemName: "clock.badge.xmark").font(.system(size: 22 * scale))
                    Text("Not in this version").font(.system(size: 12 * scale))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cardEditing && node.fileType == .markdown {
                TextEditor(text: $cardDraft)
                    .font(.system(size: 13 * scale, design: .monospaced))
                    .padding(8 * scale)
            } else {
                switch node.fileType {
                case .markdown:
                    ScrollView {
                        MarkdownView(text: cardText, scale: scale)
                            .padding(12 * scale)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .csv:
                    CSVTableView(text: cardText, scale: scale)
                case .code:
                    CodeView(text: cardText, language: node.codeLanguage, scale: scale)
                case .text:
                    ScrollView {
                        Text(cardText.isEmpty ? "Empty file" : cardText)
                            .font(.system(size: 13 * scale, design: .monospaced))
                            .foregroundStyle(cardText.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .padding(12 * scale)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Bound the body's hit-testing to its own frame. Selectable code text in a 2-axis ScrollView
        // (`CodeView`, with `.fixedSize(horizontal:)`) otherwise reports a hit region as wide as the
        // longest line — an invisible strip that escapes the visual clip and eats clicks on other
        // boxes ("can't select anything after expanding the code demo"). `.clipped()` clips interaction.
        .contentShape(Rectangle())
        .clipped()
    }

    private func toggleCardEdit() {
        if cardEditing {                                  // leaving edit → persist
            model.saveFileContent(node.id, cardDraft)
            cardText = cardDraft
            model.endEditingFile(node.id)
        } else {
            cardDraft = cardText
            model.beginEditingFile(node.id)
        }
        withAnimation(.easeInOut(duration: 0.12)) { cardEditing.toggle() }
    }

    /// The file changed on disk while this card was mid-edit; reload it, discarding the local draft.
    private func reloadFromDisk() {
        let fresh = model.fileText(node.id)
        cardText = fresh; cardDraft = fresh
        cardEditing = false
        model.endEditingFile(node.id)   // also clears the conflict
    }

    private var hasCustomColor: Bool { node.colorName != nil }

    private var noteIconName: String {
        switch node.fileType {
        case .markdown: return "doc.text.fill"
        case .csv:      return "tablecells.fill"
        case .code:     return "chevron.left.forward.slash.chevron.right"
        case .text:     return "doc.plaintext.fill"
        }
    }

    // Note box
    private var noteBox: some View {
        VStack(spacing: 6 * scale * node.sizeScale) {
            Image(systemName: noteIconName)
                .foregroundStyle(hasCustomColor ? node.accent : Color.secondary)
                .font(.system(size: 15 * scale * node.sizeScale))
            title.font(.system(size: 14 * node.fontScaleValue * scale * node.sizeScale, weight: .medium))
        }
        .padding(10 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12 * scale)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: (isSelected ? 7 : 4) * scale, y: 2 * scale)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12 * scale)
                .stroke(noteBorderColor, lineWidth: (isSelected ? 2.5 : (hasCustomColor ? 1.5 : 1)) * scale)
        )
    }

    private var noteBorderColor: Color {
        if isSelected { return node.accent }
        return hasCustomColor ? node.accent.opacity(0.55) : Color.black.opacity(0.08)
    }

    // Folder box (container)
    private var folderBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6 * scale) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(node.accent)
                    .font(.system(size: 15 * scale))
                title.font(.system(size: 14 * node.fontScaleValue * scale, weight: .semibold))
                Spacer(minLength: 4 * scale)
                Button {
                    withAnimation(gappSpring) { _ = model.addChildNote(inFolder: node) }
                } label: {
                    Image(systemName: "plus").font(.system(size: 11 * scale, weight: .bold))
                }
                .buttonStyle(.borderless)
                .help("Add note in this folder")
            }
            .padding(.horizontal, 12 * scale)
            .frame(height: headerHeight * scale)
            .background(node.accent.opacity(0.14))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14 * scale).fill(node.accent.opacity(0.045)))
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
        .overlay(
            RoundedRectangle(cornerRadius: 14 * scale)
                .stroke(isSelected ? node.accent : node.accent.opacity(0.4),
                        style: StrokeStyle(lineWidth: (isSelected ? 2.5 : 1.5) * scale,
                                           dash: isSelected ? [] : [6 * scale, 4 * scale]))
        )
    }

    @ViewBuilder
    private var title: some View {
        if isEditing {
            InlineTitle(node: node)
        } else {
            Text(node.name).lineLimit(2).multilineTextAlignment(.center)
        }
    }

    /// Boxes a context action applies to: the whole selection if this box is part of a
    /// multi-selection, otherwise just this box.
    private var menuTargets: Set<UUID> {
        model.selection.contains(node.id) && model.selection.count > 1
            ? model.selection : [node.id]
    }

    @ViewBuilder
    private var menu: some View {
        Button("Rename") { model.editingId = node.id; model.selection = [node.id] }
        if node.kind == .note {
            Button(node.isExpanded ? "Collapse Card" : "Expand Card") {
                withAnimation(gappSpring) { model.toggleExpand(node.id) }
            }
            Button("Quick Look") { withAnimation(gappSpring) { model.openPeek(node.id) } }
        }
        if node.kind == .folder {
            Button("Add Note Inside") { withAnimation(gappSpring) { _ = model.addChildNote(inFolder: node) } }
        }
        Divider()
        Menu("Color") {
            Button("Default") { model.setColor(menuTargets, nil) }
            Divider()
            ForEach(BoxColor.allCases) { c in
                Button(c.label) { model.setColor(menuTargets, c) }
            }
        }
        Menu("Text Size") {
            ForEach(TextSize.allCases) { s in
                Button {
                    model.setTextSize(menuTargets, s)
                } label: {
                    if TextSize.from(scale: node.fontScaleValue) == s {
                        Label(s.label, systemImage: "checkmark")
                    } else {
                        Text(s.label)
                    }
                }
            }
        }
        Divider()
        Button("Reveal in Finder") { model.revealInFinder(node.id) }
        if node.kind == .note {
            Button("Open in Default App") { model.openInDefaultApp(node.id) }
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            withAnimation(gappSpring) { model.delete(menuTargets) }
        }
    }

    private func select() {
        model.editingId = nil
        model.selectedEdge = nil
        // Shift-click adds/removes this box from the selection; a plain click selects only it.
        if NSEvent.modifierFlags.contains(.shift) {
            if model.selection.contains(node.id) { model.selection.remove(node.id) }
            else { model.selection.insert(node.id) }
        } else {
            model.selection = [node.id]
        }
    }

    private func handleDoubleTap(at local: CGPoint) {
        model.selection = [node.id]
        // `local` is in the box's scaled (screen) space; divide by scale to get content units.
        let cx = local.x / scale, cy = local.y / scale
        if node.kind == .folder, cy > headerHeight {
            // Double-click the folder's interior -> a note inside it, where you clicked.
            let world = CGPoint(x: displayFrame.minX + cx, y: displayFrame.minY + cy)
            withAnimation(gappSpring) { _ = model.addNote(inDir: node.relPath, at: world) }
        } else {
            model.editingId = node.id
        }
    }

    // MARK: Drag to move (folders carry their contents; drop into a folder to re-file)

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { v in
                if groupStart.isEmpty {
                    // Dragging a box that isn't selected collapses the selection to just it; dragging
                    // one that's part of a multi-selection moves the whole group.
                    if !model.selection.contains(node.id) { model.selection = [node.id] }
                    model.editingId = nil
                    model.selectedEdge = nil
                    // ⌥-drag duplicates in place first (its own undo step), then this gesture drags the
                    // new copies — so the originals stay put and the duplicates follow the cursor. A
                    // single-box ⌥-drag yields one copy, whose id becomes the re-file/settle root.
                    let multiSelected = model.selection.count > 1
                    if NSEvent.modifierFlags.contains(.option) {
                        let copies = model.duplicate(model.selection, offset: .zero)
                        dragIds = copies.flatMap { model.dragGroup(for: $0) }.reduce(into: Set()) { $0.insert($1) }
                        dragRootId = multiSelected ? nil : copies.first
                    } else {
                        dragIds = model.dragGroup(for: node.id)
                        dragRootId = node.id
                    }
                    model.beginInteraction()
                    groupMultiSelect = multiSelected
                    var dict: [UUID: CGPoint] = [:]
                    for id in dragIds {
                        if let n = model.node(id) { dict[id] = n.center }
                    }
                    groupStart = dict
                }
                let dx = v.translation.width / model.zoom
                let dy = v.translation.height / model.zoom
                for (id, c) in groupStart {
                    model.setPosition(id, to: CGPoint(x: c.x + dx, y: c.y + dy))
                }
                // Live drop-target highlight (single-box drags only; group moves never re-file).
                model.dropTargetId = (groupMultiSelect ? nil : dragRootId)
                    .map { model.dropTargetHighlight(for: $0, at: model.worldFromGlobal(v.location)) } ?? nil
            }
            .onEnded { v in
                let multi = groupMultiSelect
                let root = dragRootId
                groupStart = [:]
                groupMultiSelect = false
                dragIds = []
                dragRootId = nil
                // Single-box drag re-files into the folder under the drop point; group moves reposition only.
                if multi || root == nil { model.endInteraction() }
                else if let root { model.endDrag(root, at: model.worldFromGlobal(v.location)) }
            }
    }
}

// MARK: - Inline rename field

struct InlineTitle: View {
    @EnvironmentObject var model: AppModel
    let node: BoardNode
    @State private var text: String = ""
    @State private var cancelled = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .focused($focused)
            .onAppear {
                text = node.name
                focused = true
                // Pre-select the text so typing replaces "Untitled".
                DispatchQueue.main.async {
                    if let tv = NSApp.keyWindow?.firstResponder as? NSTextView {
                        tv.selectAll(nil)
                    }
                }
            }
            .onSubmit { commit() }
            .onExitCommand { cancelled = true; finish() }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        if !cancelled { model.rename(node.id, to: text) }
        finish()
    }

    private func finish() {
        if model.editingId == node.id { model.editingId = nil }
    }
}

// MARK: - Corner resize handle (notes & folders)

enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

struct ResizeHandle: View {
    @EnvironmentObject var model: AppModel
    let node: BoardNode
    let corner: Corner
    @State private var startFrame: CGRect?

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        if startFrame == nil {
                            startFrame = model.effectiveFrame(of: node)
                            model.beginInteraction()
                        }
                        guard let s = startFrame else { return }
                        let dx = v.translation.width / model.zoom
                        let dy = v.translation.height / model.zoom
                        let grid = AppModel.gridStep
                        func snap(_ p: CGFloat) -> CGFloat { (p / grid).rounded() * grid }
                        // Opposite corner is the fixed anchor; the dragged corner moves by (dx,dy),
                        // snapped to the dot grid. `sign` is the drag's direction from the anchor.
                        let anchor: CGPoint, sign: CGVector, drag: CGPoint
                        switch corner {
                        case .topLeft:     anchor = CGPoint(x: s.maxX, y: s.maxY); sign = CGVector(dx: -1, dy: -1); drag = CGPoint(x: snap(s.minX + dx), y: snap(s.minY + dy))
                        case .topRight:    anchor = CGPoint(x: s.minX, y: s.maxY); sign = CGVector(dx:  1, dy: -1); drag = CGPoint(x: snap(s.maxX + dx), y: snap(s.minY + dy))
                        case .bottomLeft:  anchor = CGPoint(x: s.maxX, y: s.minY); sign = CGVector(dx: -1, dy:  1); drag = CGPoint(x: snap(s.minX + dx), y: snap(s.maxY + dy))
                        case .bottomRight: anchor = CGPoint(x: s.minX, y: s.minY); sign = CGVector(dx:  1, dy:  1); drag = CGPoint(x: snap(s.maxX + dx), y: snap(s.maxY + dy))
                        }
                        let minSize = node.kind == .folder ? AppModel.folderMinSize : AppModel.noteMinSize
                        model.setFrame(node.id, model.resizedFrame(for: node, anchor: anchor, drag: drag, sign: sign, minSize: minSize))
                    }
                    .onEnded { _ in startFrame = nil; model.endInteraction() }
            )
    }
}
