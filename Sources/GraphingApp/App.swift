import SwiftUI
import AppKit

@main
struct GraphingAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Graphing App") {
            RootView()
                .environmentObject(model)
                .onAppear { model.restoreLastVault() }
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    NotificationCenter.default.post(name: .newNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("New Folder") {
                    NotificationCenter.default.post(name: .newFolder, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                // ⌘Z / ⇧⌘Z must undo the *text field's* typing while a title (or card body) is being
                // edited — not the board. The canvas key monitor already bails for a focused field; this
                // menu command was the one board-undo path that wasn't first-responder-aware (the leak).
                // No `.disabled` gate: field-focus isn't a SwiftUI-observable dependency, so a stale
                // `.disabled` could swallow ⌘Z right when a field starts editing on an empty board. The
                // routed closure is no-op-safe either way (field checks canUndo; performUndo/Redo guard
                // an empty stack), so leaving the items always enabled is correct, not just lazy.
                Button("Undo") { FieldEditor.undoIfEditing(else: model.performUndo) }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { FieldEditor.redoIfEditing(else: model.performRedo) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                // ⌘= shares a key with ⌘+ (+ is shift-=), so binding "=" makes ⌘+ work without Shift.
                Button("Zoom In") { model.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { model.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { model.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Zoom to Fit") { model.zoomToFit() }
                    .keyboardShortcut("9", modifiers: .command)
                Divider()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.installCrashHandlers()
        Log.app.notice("GraphingApp launched")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        Log.app.notice("GraphingApp terminating")
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension Notification.Name {
    static let newNote = Notification.Name("gapp.newNote")
    static let newFolder = Notification.Name("gapp.newFolder")
}

// MARK: - First-responder-aware undo

/// Routes ⌘Z / ⇧⌘Z to the focused text field's *own* undo manager while a title rename or card
/// body is being edited, so typing is undone field-locally instead of mutating the board. When no
/// field editor is first responder, the caller's board undo/redo runs instead.
enum FieldEditor {
    /// The undo manager of the field editor (`NSTextView`) currently editing a SwiftUI TextField.
    /// `NSTextView` is the field editor SwiftUI's TextField focuses; only it carries the per-field
    /// typing undo we want to route to.
    private static var current: UndoManager? {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager
    }

    static var isEditing: Bool { current != nil }

    static func undoIfEditing(else boardUndo: () -> Void) {
        if let undoManager = current { if undoManager.canUndo { undoManager.undo() } }
        else { boardUndo() }
    }

    static func redoIfEditing(else boardRedo: () -> Void) {
        if let undoManager = current { if undoManager.canRedo { undoManager.redo() } }
        else { boardRedo() }
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.vault == nil {
                WelcomeView()
            } else {
                MainView()
            }
        }
        .preferredColorScheme(model.lightTheme ? .light : .dark)
    }
}

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.grid.3x3.topleft.filled")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Graphing App")
                .font(.largeTitle.bold())
            Text("A tiny Miro-style canvas that organizes folders\nand creates Obsidian .md notes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                model.chooseVault()
            } label: {
                Label("Choose Vault Folder…", systemImage: "folder")
                    .padding(.horizontal, 8)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Main layout

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSidebar = true

    var body: some View {
        VStack(spacing: 0) {
            TopBar(showSidebar: $showSidebar)
            Divider()
            HStack(spacing: 0) {
                if showSidebar {
                    SidebarView()
                        .frame(width: 240)
                    Divider()
                }
                CanvasView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @Binding var showSidebar: Bool
    @State private var showHistory = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.borderless)
            .help("Toggle sidebar")

            Image(systemName: "folder.fill").foregroundStyle(.secondary)
            Text(model.vaultName).fontWeight(.medium)

            Divider().frame(height: 18)

            Button { newNoteAtCenter() } label: {
                Label("Note", systemImage: "doc.badge.plus")
            }
            .help("New note (⌘N)")

            Button { newFolderAtCenter() } label: {
                Label("Folder", systemImage: "folder.badge.plus")
            }
            .help("New folder (⇧⌘N)")

            Divider().frame(height: 18)

            Button { model.performUndo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless)
                .disabled(!model.canUndo)
                .help("Undo (⌘Z)")
            Button { model.performRedo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(.borderless)
                .disabled(!model.canRedo)
                .help("Redo (⇧⌘Z)")

            Spacer()

            // Zoom controls
            HStack(spacing: 4) {
                Button { model.zoomToFit() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.borderless)
                    .help("Zoom to fit (⌘9)")
                Button { model.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help("Zoom out (⌘−)")
                Button { model.resetZoom() } label: {
                    Text("\(Int((model.zoom * 100).rounded()))%")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 44)
                }
                .buttonStyle(.borderless)
                .help("Reset to 100% (⌘0)")
                Button { model.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help("Zoom in (⌘+)")
            }

            Button { showHistory.toggle() } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(model.versionHistoryEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .buttonStyle(.borderless)
            .help("Version history")
            .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                VersionHistoryView().environmentObject(model)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { model.lightTheme.toggle() }
            } label: {
                Image(systemName: model.lightTheme ? "moon.fill" : "sun.max.fill")
            }
            .buttonStyle(.borderless)
            .help(model.lightTheme ? "Switch to dark theme" : "Switch to light theme")

            Button { model.closeVault() } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.borderless)
            .help("Close vault")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func centerWorld() -> CGPoint {
        model.screenToWorld(CGPoint(x: model.viewport.width / 2, y: model.viewport.height / 2))
    }

    private func newNoteAtCenter() { model.addNote(inDir: "", at: centerWorld()) }
    private func newFolderAtCenter() { model.addFolder(inDir: "", at: centerWorld()) }
}
