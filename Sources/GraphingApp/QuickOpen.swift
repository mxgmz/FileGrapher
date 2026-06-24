import SwiftUI

// MARK: - Quick-open palette (⌘P)

/// Fuzzy-jump search over every board node by name. The pure matcher (`quickOpenMatches`) and the
/// pan-to-and-select reveal (`revealNode`) live in the AppModel extension below so Model.swift stays
/// untouched. Reveal reuses the existing `center(on:)` (pan so the node's worldCenter lands at the
/// viewport center, keep current zoom, select it).
extension AppModel {
    /// At most this many rows — a quick-open list is for jumping, not browsing the whole vault.
    static let quickOpenLimit = 20

    /// Board nodes whose name contains `query` (case-insensitive), ranked: exact prefix matches first,
    /// then mid-string substrings; ties broken alphabetically. An empty query returns all nodes (capped),
    /// so opening the palette previews the whole board.
    func quickOpenMatches(_ query: String) -> [BoardNode] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return Array(board.nodes.sorted { $0.name.lowercased() < $1.name.lowercased() }.prefix(AppModel.quickOpenLimit))
        }
        let ranked = board.nodes.compactMap { node -> (BoardNode, Bool)? in
            let name = node.name.lowercased()
            guard name.contains(needle) else { return nil }
            return (node, name.hasPrefix(needle))
        }
        let sorted = ranked.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 }   // prefix matches rank above mid-string substrings
            return lhs.0.name.lowercased() < rhs.0.name.lowercased()
        }
        return Array(sorted.map(\.0).prefix(AppModel.quickOpenLimit))
    }

    /// Pan/zoom to center `id`'s worldFrame, select it, and close the palette.
    func revealNode(_ id: UUID) {
        center(on: id)   // pans so worldCenter lands at the viewport center + selects; keeps current zoom
        quickOpenVisible = false
    }
}

struct QuickOpenView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private var matches: [BoardNode] { model.quickOpenMatches(query) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Jump to note or folder…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($fieldFocused)
                .onSubmit(selectHighlighted)
                .onChange(of: query) { highlighted = 0 }

            if !matches.isEmpty {
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, node in
                            QuickOpenRow(node: node, isHighlighted: index == highlighted)
                                .contentShape(Rectangle())
                                .onTapGesture { model.revealNode(node.id) }
                                .onHover { if $0 { highlighted = index } }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.25)))
        .shadow(radius: 24, y: 8)
        .onAppear { fieldFocused = true }
        .onKeyPress(.downArrow) { moveHighlight(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveHighlight(by: -1); return .handled }
        .onKeyPress(.escape) { model.quickOpenVisible = false; return .handled }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 120)
        .background(QuickOpenBackdrop { model.quickOpenVisible = false })
    }

    private func moveHighlight(by delta: Int) {
        guard !matches.isEmpty else { return }
        highlighted = min(max(highlighted + delta, 0), matches.count - 1)
    }

    private func selectHighlighted() {
        guard matches.indices.contains(highlighted) else { return }
        model.revealNode(matches[highlighted].id)
    }
}

/// One result row: folder/note icon + title, tinted when highlighted.
private struct QuickOpenRow: View {
    let node: BoardNode
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: node.kind == .folder ? "folder.fill" : "doc.text")
                .foregroundStyle(node.kind == .folder ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 18)
            Text(node.name).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHighlighted ? Color.accentColor.opacity(0.18) : .clear)
    }
}

/// Dim, click-to-dismiss scrim behind the palette.
private struct QuickOpenBackdrop: View {
    let onDismiss: () -> Void
    var body: some View {
        Color.black.opacity(0.18)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
    }
}
