import SwiftUI

struct TreeItem: Identifiable {
    let id: UUID
    let node: BoardNode
    var children: [TreeItem]?
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    private var tree: [TreeItem] {
        func children(of dir: String) -> [TreeItem] {
            let kids = model.board.nodes
                .filter { $0.parentRel == dir }
                .sorted { lhs, rhs in
                    if lhs.kind != rhs.kind { return lhs.kind == .folder }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            return kids.map { n in
                let sub = n.kind == .folder ? children(of: n.relPath) : []
                return TreeItem(id: n.id, node: n, children: sub.isEmpty ? nil : sub)
            }
        }
        return children(of: "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FILES")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button { model.syncFromDisk() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Rescan vault from disk")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if model.board.nodes.isEmpty {
                Spacer()
                Text("No notes yet.\nDouble-click the canvas to add one.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List {
                    OutlineGroup(tree, children: \.children) { item in
                        SidebarRow(node: item.node)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SidebarRow: View {
    @EnvironmentObject var model: AppModel
    let node: BoardNode

    private var isSelected: Bool { model.selection.contains(node.id) }

    private var iconName: String {
        guard node.kind == .note else { return "folder.fill" }
        switch node.fileType {
        case .markdown: return "doc.text"
        case .csv:      return "tablecells"
        case .code:     return "chevron.left.forward.slash.chevron.right"
        case .text:     return "doc.plaintext"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(node.kind == .folder ? Color.accentColor : Color.secondary)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.center(on: node.id)
        }
        .contextMenu {
            Button("Reveal on Canvas") { model.center(on: node.id) }
            if node.kind == .note {
                Button(node.isExpanded ? "Collapse Card" : "Expand Card") {
                    model.center(on: node.id)
                    withAnimation(gappSpring) { model.toggleExpand(node.id) }
                }
                Button("Quick Look") {
                    model.center(on: node.id)
                    withAnimation(gappSpring) { model.openPeek(node.id) }
                }
            }
            Button("Rename") { model.editingId = node.id; model.selection = [node.id] }
            Divider()
            Menu("Color") {
                Button("Default") { model.setColor([node.id], nil) }
                Divider()
                ForEach(BoxColor.allCases) { c in
                    Button(c.label) { model.setColor([node.id], c) }
                }
            }
            Menu("Text Size") {
                ForEach(TextSize.allCases) { s in
                    Button {
                        model.setTextSize([node.id], s)
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
            Button("Move to Trash", role: .destructive) { model.delete([node.id]) }
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }
}
