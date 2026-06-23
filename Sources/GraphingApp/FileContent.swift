import SwiftUI
import AppKit

// MARK: - File content peek (floating card)

/// Backdrop + floating card showing the peeked box's file content. Tap-outside / Esc / ✕ closes.
/// Lives in the canvas ZStack, so it positions in canvas-local coordinates like the boxes do.
struct FilePeekOverlay: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let id = model.peekId, let node = model.node(id) {
            ZStack {
                Color.black.opacity(0.18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(gappSpring) { model.closePeek() } }
                FilePeekCard(node: node)
                    .frame(width: cardWidth, height: cardHeight)
                    .position(cardCenter(for: node))
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
    }

    private let cardWidth: CGFloat = 460
    private var cardHeight: CGFloat { min(max(model.viewport.height - 56, 240), 660) }

    /// Place the card beside the box, clamped to stay fully on the canvas.
    private func cardCenter(for node: BoardNode) -> CGPoint {
        let f = model.effectiveFrame(of: node)
        let c = model.worldToScreen(CGPoint(x: f.midX, y: f.midY))
        let halfBoxW = f.width * model.zoom / 2
        let margin: CGFloat = 16
        let vp = model.viewport
        var x = c.x + halfBoxW + margin + cardWidth / 2            // prefer right of the box
        if x + cardWidth / 2 > vp.width - margin {                 // no room → left of the box
            x = c.x - halfBoxW - margin - cardWidth / 2
        }
        x = min(max(x, margin + cardWidth / 2), max(margin + cardWidth / 2, vp.width - margin - cardWidth / 2))
        let y = min(max(c.y, margin + cardHeight / 2),
                    max(margin + cardHeight / 2, vp.height - margin - cardHeight / 2))
        return CGPoint(x: x, y: y)
    }
}

/// The card itself: header (name + edit/open/close) over the rendered or editable content.
struct FilePeekCard: View {
    @EnvironmentObject var model: AppModel
    let node: BoardNode
    @State private var editing = false
    @State private var draft = ""
    @State private var loaded = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(node.accent.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 20, y: 8)
        .onAppear { loaded = model.fileText(node.id); draft = loaded }
        .onDisappear { if editing { model.saveFileContent(node.id, draft) } }
        .onChange(of: node.id) { _, _ in
            if editing { model.saveFileContent(node.id, draft) }
            editing = false; loaded = model.fileText(node.id); draft = loaded
        }
        .onChange(of: model.diskRevision) { _, _ in
            guard !editing else { return }   // don't clobber an in-progress edit
            let fresh = model.fileText(node.id)
            if fresh != loaded { loaded = fresh; draft = fresh }
        }
        .onChange(of: model.viewedCommit) { _, _ in
            editing = false   // history is read-only
            loaded = model.fileText(node.id); draft = loaded
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName).foregroundStyle(node.accent)
            Text(node.name).fontWeight(.semibold).lineLimit(1)
            Spacer(minLength: 8)
            if model.isTimeTraveling {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.orange)
                    .help("Viewing history — read-only")
            } else if node.fileType == .markdown {
                Button { toggleEdit() } label: {
                    Image(systemName: editing ? "eye" : "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help(editing ? "Preview" : "Edit")
            }
            Button { model.openInDefaultApp(node.id) } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.borderless).help("Open in default app")
            Button { withAnimation(gappSpring) { model.closePeek() } } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).help("Close (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if model.isAbsentInHistory(node.id) {
            VStack(spacing: 8) {
                Image(systemName: "clock.badge.xmark").font(.system(size: 26))
                Text("Not in this version").font(.callout)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        } else {
            liveContent
        }
    }

    @ViewBuilder
    private var liveContent: some View {
        switch node.fileType {
        case .markdown:
            if editing {
                TextEditor(text: $draft)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
            } else {
                ScrollView {
                    MarkdownView(text: loaded)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .csv:
            CSVTableView(text: loaded)
        case .code:
            CodeView(text: loaded, language: node.codeLanguage)
        case .text:
            ScrollView {
                Text(loaded.isEmpty ? "Empty file" : loaded)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(loaded.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var iconName: String {
        switch node.fileType {
        case .markdown: return "doc.text.fill"
        case .csv:      return "tablecells.fill"
        case .code:     return "chevron.left.forward.slash.chevron.right"
        case .text:     return "doc.plaintext.fill"
        }
    }

    private func toggleEdit() {
        if editing {                                   // leaving edit → persist
            model.saveFileContent(node.id, draft)
            loaded = draft
        } else {
            draft = loaded
        }
        withAnimation(.easeInOut(duration: 0.15)) { editing.toggle() }
    }
}

// MARK: - Markdown renderer (lightweight block parser, zero deps)

struct MarkdownView: View {
    let text: String
    var scale: CGFloat = 1   // screen-space multiplier (1 in the fixed-size peek; = zoom in cards)

    var body: some View {
        let blocks = MarkdownBlock.parse(text)
        VStack(alignment: .leading, spacing: 10 * scale) {
            if blocks.isEmpty {
                Text("Empty file").foregroundStyle(.secondary)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    block.view(scale: scale)
                }
            }
        }
        .textSelection(.enabled)
    }
}

/// Inline-only markdown → AttributedString (bold/italic/code/links), block syntax ignored.
func gappInlineMarkdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}

enum MarkdownBlock {
    case heading(Int, String)
    case paragraph(String)
    case bullet([String])
    case ordered([String])
    case quote(String)
    case code(String)
    case rule

    @ViewBuilder func view(scale: CGFloat) -> some View {
        let body = 14 * scale
        switch self {
        case .heading(let level, let t):
            Text(gappInlineMarkdown(t))
                .font(.system(size: Self.headingSize(level) * scale, weight: .bold))
                .padding(.top, (level <= 2 ? 4 : 0) * scale)
        case .paragraph(let t):
            Text(gappInlineMarkdown(t)).font(.system(size: body)).fixedSize(horizontal: false, vertical: true)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4 * scale) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                        Text("•").font(.system(size: body)).foregroundStyle(.secondary)
                        Text(gappInlineMarkdown(items[i])).font(.system(size: body)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .ordered(let items):
            VStack(alignment: .leading, spacing: 4 * scale) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                        Text("\(i + 1).").font(.system(size: body)).foregroundStyle(.secondary).monospacedDigit()
                        Text(gappInlineMarkdown(items[i])).font(.system(size: body)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .quote(let t):
            HStack(alignment: .top, spacing: 8 * scale) {
                RoundedRectangle(cornerRadius: 2 * scale).fill(Color.secondary.opacity(0.5)).frame(width: 3 * scale)
                Text(gappInlineMarkdown(t)).font(.system(size: body)).italic().foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .code(let t):
            Text(t)
                .font(.system(size: 13 * scale, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10 * scale)
                .background(RoundedRectangle(cornerRadius: 8 * scale).fill(Color.secondary.opacity(0.12)))
        case .rule:
            Divider()
        }
    }

    static func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: return 26; case 2: return 21; case 3: return 18
                       case 4: return 16; case 5: return 15; default: return 14 }
    }

    // MARK: line-based parse

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var para: [String] = []
        func flush() { if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: " "))); para = [] } }

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {                                  // fenced code
                flush(); i += 1
                var code: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }
            if line.isEmpty { flush(); i += 1; continue }
            if line == "---" || line == "***" || line == "___" { flush(); blocks.append(.rule); i += 1; continue }
            if let h = heading(line) { flush(); blocks.append(.heading(h.0, h.1)); i += 1; continue }
            if line.hasPrefix(">") {                                    // blockquote run
                flush()
                var qs: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard l.hasPrefix(">") else { break }
                    qs.append(String(l.dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                blocks.append(.quote(qs.joined(separator: " ")))
                continue
            }
            if isBullet(line) {                                         // unordered list run
                flush()
                var items: [String] = []
                while i < lines.count, isBullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2))
                        .trimmingCharacters(in: .whitespaces)); i += 1
                }
                blocks.append(.bullet(items)); continue
            }
            if isOrdered(line) {                                        // ordered list run
                flush()
                var items: [String] = []
                while i < lines.count, isOrdered(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(orderedText(lines[i].trimmingCharacters(in: .whitespaces))); i += 1
                }
                blocks.append(.ordered(items)); continue
            }
            para.append(line); i += 1
        }
        flush()
        return blocks
    }

    private static func heading(_ l: String) -> (Int, String)? {
        var n = 0
        for ch in l { if ch == "#" { n += 1 } else { break } }
        guard (1...6).contains(n), l.count > n,
              l[l.index(l.startIndex, offsetBy: n)] == " " else { return nil }
        return (n, String(l.dropFirst(n)).trimmingCharacters(in: .whitespaces))
    }
    private static func isBullet(_ l: String) -> Bool {
        l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("+ ")
    }
    private static func isOrdered(_ l: String) -> Bool {
        guard let dot = l.firstIndex(of: ".") else { return false }
        let num = l[l.startIndex..<dot]
        let after = l.index(after: dot)
        return !num.isEmpty && num.allSatisfy(\.isNumber) && after < l.endIndex && l[after] == " "
    }
    private static func orderedText(_ l: String) -> String {
        guard let dot = l.firstIndex(of: ".") else { return l }
        return String(l[l.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - CSV table (read-only)

struct CSVTableView: View {
    let text: String
    var scale: CGFloat = 1
    private let rowCap = 1000

    var body: some View {
        let rows = CSV.parse(text)
        if rows.isEmpty {
            Text("Empty file")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let cols = rows.map(\.count).max() ?? 0
            let shown = Array(rows.prefix(rowCap))
            VStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(shown.indices, id: \.self) { ri in
                            HStack(spacing: 0) {
                                ForEach(Array(0..<cols), id: \.self) { ci in
                                    Text(ci < shown[ri].count ? shown[ri][ci] : "")
                                        .font(.system(size: 13 * scale, design: ri == 0 ? .default : .monospaced))
                                        .fontWeight(ri == 0 ? .semibold : .regular)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(minWidth: 80 * scale, maxWidth: 260 * scale, alignment: .leading)
                                        .padding(.horizontal, 10 * scale)
                                        .padding(.vertical, 6 * scale)
                                }
                            }
                            .background(rowBackground(ri))
                            Divider().opacity(0.25)
                        }
                    }
                }
                if rows.count > rowCap {
                    Text("Showing first \(rowCap) of \(rows.count) rows")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(.thinMaterial)
                }
            }
        }
    }

    private func rowBackground(_ i: Int) -> Color {
        if i == 0 { return Color.accentColor.opacity(0.14) }
        return i % 2 == 0 ? Color.secondary.opacity(0.06) : Color.clear
    }
}

// MARK: - Code viewer (read-only, line numbers + lightweight syntax highlighting, zero deps)

/// Token colors, chosen to read on both light and dark backgrounds.
let gappCodeKeyword = Color(red: 0.80, green: 0.40, blue: 0.64)   // pink/magenta
let gappCodeString  = Color(red: 0.84, green: 0.49, blue: 0.31)   // orange
let gappCodeComment = Color(red: 0.46, green: 0.60, blue: 0.47)   // muted green
let gappCodeNumber  = Color(red: 0.30, green: 0.64, blue: 0.69)   // teal

struct CodeView: View {
    let text: String
    var language: String = ""
    var scale: CGFloat = 1
    private let lineCap = 4000

    var body: some View {
        let rawLines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if rawLines.isEmpty {
            Text("Empty file")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let shown = Array(rawLines.prefix(lineCap))
            let lines = CodeSyntax.forLanguage(language).highlight(shown)
            let gutterW = CGFloat(String(shown.count).count) * 8.5 * scale + 10 * scale
            VStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lines.indices, id: \.self) { idx in
                            HStack(alignment: .top, spacing: 0) {
                                Text("\(idx + 1)")
                                    .font(.system(size: 12.5 * scale, design: .monospaced))
                                    .foregroundStyle(.secondary.opacity(0.55))
                                    .frame(width: gutterW, alignment: .trailing)
                                    .padding(.trailing, 8 * scale)
                                Text(lines[idx])
                                    .font(.system(size: 12.5 * scale, design: .monospaced))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                    .padding(.vertical, 8 * scale)
                    .padding(.trailing, 12 * scale)
                    .frame(minWidth: 0, alignment: .leading)
                }
                if rawLines.count > lineCap {
                    Text("Showing first \(lineCap) of \(rawLines.count) lines")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(.thinMaterial)
                }
            }
        }
    }
}

/// Per-language comment / string rules + a (deliberately broad) keyword set. Highlighting is a
/// simple single-pass tokenizer — good enough to read code, not a full grammar.
struct CodeSyntax {
    let lineComments: [String]
    let block: (open: String, close: String)?
    let stringDelims: [Character]
    let keywords: Set<String>

    func highlight(_ lines: [String]) -> [AttributedString] {
        var inBlock = false
        return lines.map { line -> AttributedString in
            let a = highlightLine(line, inBlock: &inBlock)
            return a.characters.isEmpty ? AttributedString(" ") : a   // keep empty lines tall
        }
    }

    private func matchAt(_ chars: [Character], _ i: Int, _ token: String) -> Bool {
        let t = Array(token)
        guard !t.isEmpty, i + t.count <= chars.count else { return false }
        for k in 0..<t.count where chars[i + k] != t[k] { return false }
        return true
    }

    private func highlightLine(_ line: String, inBlock: inout Bool) -> AttributedString {
        var out = AttributedString()
        func emit(_ s: String, _ color: Color?) {
            var a = AttributedString(s)
            if let color { a.foregroundColor = color }
            out += a
        }
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            if inBlock {
                if let b = block, matchAt(chars, i, b.close) {
                    emit(String(chars[i ..< i + b.close.count]), gappCodeComment)
                    i += b.close.count; inBlock = false
                } else { emit(String(chars[i]), gappCodeComment); i += 1 }
                continue
            }
            if let b = block, matchAt(chars, i, b.open) {
                emit(String(chars[i ..< i + b.open.count]), gappCodeComment)
                i += b.open.count; inBlock = true; continue
            }
            if let lc = lineComments.first(where: { matchAt(chars, i, $0) }) {
                _ = lc
                emit(String(chars[i...]), gappCodeComment); i = chars.count; continue
            }
            if let q = stringDelims.first(where: { chars[i] == $0 }) {
                var s = String(q); var j = i + 1
                while j < chars.count {
                    let c = chars[j]
                    if c == "\\", j + 1 < chars.count { s.append(c); s.append(chars[j + 1]); j += 2; continue }
                    s.append(c); j += 1
                    if c == q { break }
                }
                emit(s, gappCodeString); i = j; continue
            }
            if chars[i].isNumber {
                var s = ""; var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "_"
                        || "xXeEabcdefABCDEF".contains(chars[j]) {
                    s.append(chars[j]); j += 1
                }
                emit(s, gappCodeNumber); i = j; continue
            }
            if chars[i].isLetter || chars[i] == "_" {
                var s = ""; var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" {
                    s.append(chars[j]); j += 1
                }
                emit(s, keywords.contains(s) ? gappCodeKeyword : nil); i = j; continue
            }
            emit(String(chars[i]), nil); i += 1
        }
        return out
    }

    static func forLanguage(_ lang: String) -> CodeSyntax {
        switch lang {
        case "py", "rb", "sh", "bash", "zsh", "fish", "yaml", "yml", "toml", "ini", "conf",
             "cfg", "env", "r", "pl", "gradle", "makefile", "dockerfile":
            return CodeSyntax(lineComments: ["#"], block: nil,
                              stringDelims: ["\"", "'"], keywords: commonKeywords)
        case "sql":
            return CodeSyntax(lineComments: ["--"], block: ("/*", "*/"),
                              stringDelims: ["'", "\""], keywords: commonKeywords)
        case "lua":
            return CodeSyntax(lineComments: ["--"], block: ("--[[", "]]"),
                              stringDelims: ["\"", "'"], keywords: commonKeywords)
        case "html", "htm", "xml":
            return CodeSyntax(lineComments: [], block: ("<!--", "-->"),
                              stringDelims: ["\"", "'"], keywords: commonKeywords)
        default:   // C-family: swift, js, ts, java, kt, c/c++, cs, go, rs, php, css, json, …
            return CodeSyntax(lineComments: ["//"], block: ("/*", "*/"),
                              stringDelims: ["\"", "'", "`"], keywords: commonKeywords)
        }
    }

    /// A broad union of keywords across popular languages. Over-coloring an out-of-language word is
    /// harmless; this keeps the viewer useful without a per-language grammar.
    static let commonKeywords: Set<String> = [
        // declarations / structure
        "let", "var", "const", "func", "fn", "def", "function", "class", "struct", "enum", "interface",
        "protocol", "extension", "trait", "impl", "namespace", "module", "mod", "package", "import",
        "from", "export", "using", "use", "include", "require", "typedef", "typealias", "type",
        "template", "typename", "where", "associatedtype",
        // control flow
        "if", "else", "elif", "for", "while", "switch", "case", "default", "match", "guard", "do",
        "try", "catch", "finally", "except", "raise", "throw", "throws", "return", "yield", "break",
        "continue", "goto", "defer", "loop", "in", "of", "with", "pass", "select", "range",
        // values / operators
        "true", "false", "nil", "null", "none", "undefined", "self", "super", "this", "new", "delete",
        "is", "as", "and", "or", "not", "void", "typeof", "instanceof", "sizeof", "lambda",
        // modifiers / types
        "public", "private", "protected", "internal", "fileprivate", "static", "final", "override",
        "abstract", "virtual", "mutating", "async", "await", "lazy", "weak", "unowned", "open", "pub",
        "mut", "extends", "implements", "init", "deinit", "global", "nonlocal", "chan", "map", "go",
        "int", "long", "short", "float", "double", "char", "bool", "string", "boolean", "unsigned",
        "signed", "auto", "constexpr", "inline"
    ]
}

/// Minimal RFC-4180-ish CSV parser (quoted fields, escaped quotes, CRLF).
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 2; continue }
                    inQuotes = false; i += 1
                } else { field.append(c); i += 1 }
            } else {
                switch c {
                case "\"": inQuotes = true; i += 1
                case ",":  row.append(field); field = ""; i += 1
                case "\n": row.append(field); rows.append(row); row = []; field = ""; i += 1
                case "\r": i += 1
                default:   field.append(c); i += 1
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        if let last = rows.last, last.count == 1, last[0].isEmpty { rows.removeLast() }
        return rows
    }
}
