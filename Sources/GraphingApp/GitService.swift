import Foundation

/// Zero-dependency, **view-only** wrapper over the `git` CLI for the open vault — the plumbing for
/// Living Canvas time-travel. It reads history; it does not restore it.
///
/// VIEW-ONLY by contract. The ONLY operations that touch disk are the two explicit, opt-in writes:
///   • `enableVersionHistory()` — `git init`, ignore the `.graphingapp/` layout sidecar, baseline commit;
///   • `snapshot(_:)` — commit the current working tree when the user asks ("Snapshot").
/// It never checks out, resets, or restores: the working tree stays at the live state, and past
/// commits are read with `git show` / `git diff`. Pure Foundation (like `ManagedLinks`) so the logic
/// is headless-testable; all process I/O is synchronous and meant to run off the main thread.
struct GitService {
    let root: URL

    /// One entry in the vault's history, newest-first as `git log` returns it.
    struct Commit: Identifiable, Equatable, Sendable {
        let hash: String          // full SHA-1
        let shortHash: String
        let subject: String
        let author: String
        let date: Date
        let relativeDate: String  // git's "2 hours ago"
        var id: String { hash }
    }

    // MARK: Read-only queries

    /// True when `root` is itself the top of a git work tree (not merely nested inside one).
    var isRepo: Bool {
        let result = run(["rev-parse", "--show-toplevel"])
        guard result.ok else { return false }
        let top = URL(fileURLWithPath: result.out.trimmed).resolvingSymlinksInPath().path
        return top == root.resolvingSymlinksInPath().path
    }

    /// The current branch (e.g. "main"), or "" when detached or not a repo.
    func currentBranch() -> String {
        let name = run(["rev-parse", "--abbrev-ref", "HEAD"]).out.trimmed
        return name == "HEAD" ? "" : name
    }

    /// Local branch names.
    func branches() -> [String] {
        let result = run(["branch", "--format=%(refname:short)"])
        guard result.ok else { return [] }
        return result.out.split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    /// Newest-first commits (subject, author, dates), capped at `limit`.
    func commits(limit: Int = 200) -> [Commit] {
        // Unit-separator (\u{1f}) between fields so a subject's own spaces/punctuation parse cleanly.
        let format = ["%H", "%h", "%an", "%aI", "%ar", "%s"].joined(separator: "\u{1f}")
        let result = run(["log", "--max-count=\(limit)", "--pretty=format:\(format)"])
        guard result.ok else { return [] }
        let iso = ISO8601DateFormatter()
        return result.out.split(separator: "\n").compactMap { line in
            let fields = line.components(separatedBy: "\u{1f}")
            guard fields.count == 6 else { return nil }
            return Commit(hash: fields[0], shortHash: fields[1], subject: fields[5],
                          author: fields[2], date: iso.date(from: fields[3]) ?? Date(),
                          relativeDate: fields[4])
        }
    }

    /// Number of uncommitted changes (modified, added, deleted, untracked) in the working tree —
    /// so the UI can tell whether a Snapshot would do anything.
    func uncommittedChangeCount() -> Int {
        let result = run(["status", "--porcelain"])
        guard result.ok else { return 0 }
        return result.out.split(separator: "\n").filter { !$0.isEmpty }.count
    }

    /// Contents of `path` (vault-relative) as of `commit`, or nil when the file didn't exist there.
    func show(_ path: String, at commit: String) -> String? {
        let result = run(["show", "\(commit):\(path)"])
        return result.ok ? result.out : nil
    }

    /// Vault-relative paths of every file tracked at `commit` (`git ls-tree -r --name-only`). Used to
    /// find files that existed then but are gone now (the deleted-since ghosts).
    func filesAtCommit(_ commit: String) -> [String] {
        // core.quotePath=false keeps non-ASCII paths literal instead of octal-escaped.
        let result = run(["-c", "core.quotePath=false", "ls-tree", "-r", "--name-only", commit])
        guard result.ok else { return [] }
        return result.out.split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    /// Files changed between two commits as (status, path) — status is git's A/M/D/R… code. For a
    /// rename the new path is reported.
    func diffNameStatus(from: String, to: String) -> [(status: String, path: String)] {
        let result = run(["diff", "--name-status", from, to])
        guard result.ok else { return [] }
        return result.out.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2, let status = parts.first, let path = parts.last else { return nil }
            return (status.trimmed, path.trimmed)
        }
    }

    // MARK: Opt-in writes (the only two — both explicit, neither touches existing file contents)

    /// Turn the vault into a git repo: `git init`, ignore the `.graphingapp/` sidecar (so layout never
    /// time-travels — spec §5.3 "stable stage"), then commit everything as the baseline. Idempotent:
    /// a no-op returning true if already a repo. Returns false on failure.
    @discardableResult
    func enableVersionHistory() -> Bool {
        if isRepo { return true }
        guard run(["init"]).ok else { return false }
        ignoreSidecar()
        guard run(["add", "-A"]).ok else { return false }
        return commit("Enable Version History — baseline snapshot")
    }

    /// Commit the current working tree on demand (the manual "Snapshot"). Returns false when there is
    /// nothing to commit (so the UI can say so) or on error.
    @discardableResult
    func snapshot(_ message: String = "") -> Bool {
        guard isRepo, run(["add", "-A"]).ok, hasStagedChanges else { return false }
        let trimmed = message.trimmed
        return commit(trimmed.isEmpty ? "Snapshot \(GitService.timestamp())" : trimmed)
    }

    // MARK: Internals

    private struct Run {
        let status: Int32
        let out: String
        let err: String
        var ok: Bool { status == 0 }
    }

    /// True when something is staged — `diff --cached --quiet` exits 1 when there are staged changes,
    /// 0 when the index matches HEAD. Lets `snapshot` avoid a "nothing to commit" failure.
    private var hasStagedChanges: Bool { run(["diff", "--cached", "--quiet"]).status == 1 }

    private func commit(_ message: String) -> Bool {
        var args = ["commit", "-m", message]
        if !hasIdentity {
            // A throwaway/test repo may have no global user.name/email; supply a local one so the
            // commit doesn't fail. A real vault uses the user's own git identity.
            args = ["-c", "user.name=GraphingApp", "-c", "user.email=graphingapp@localhost"] + args
        }
        return run(args).ok
    }

    private var hasIdentity: Bool { !run(["config", "user.email"]).out.trimmed.isEmpty }

    /// Ensure `.gitignore` lists the `.graphingapp/` sidecar so positions/sizes never enter history.
    private func ignoreSidecar() {
        let gitignore = root.appendingPathComponent(".gitignore")
        let entry = ".graphingapp/"
        var text = (try? String(contentsOf: gitignore, encoding: .utf8)) ?? ""
        let present = text.split(separator: "\n", omittingEmptySubsequences: false)
            .contains(where: { $0.trimmed == entry })
        if present { return }
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += entry + "\n"
        try? text.data(using: .utf8)?.write(to: gitignore, options: .atomic)
    }

    /// Run a git subcommand inside the vault. Captures stdout/stderr; stderr drains on a side queue so
    /// a large stderr can't deadlock against a large stdout.
    @discardableResult
    private func run(_ args: [String]) -> Run {
        guard let gitURL = GitService.gitURL else {
            return Run(status: -1, out: "", err: "git executable not found")
        }
        let process = Process()
        process.executableURL = gitURL
        process.arguments = ["-C", root.path] + args
        process.environment = GitService.environment
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do { try process.run() } catch {
            return Run(status: -1, out: "", err: error.localizedDescription)
        }
        var errData = Data()
        let drain = DispatchQueue(label: "app.graphing.git.stderr")
        drain.async { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        drain.sync {}
        return Run(status: process.terminationStatus,
                   out: String(decoding: outData, as: UTF8.self),
                   err: String(decoding: errData, as: UTF8.self))
    }

    /// First `git` found on a standard path. Command Line Tools install `/usr/bin/git`; Homebrew puts
    /// it under `/opt/homebrew` or `/usr/local`.
    private static let gitURL: URL? = {
        for path in ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }()

    private static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"   // never block waiting on a credential prompt
        env["GIT_OPTIONAL_LOCKS"] = "0"    // don't take the index lock for read-only queries
        return env
    }()

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date())
    }
}

private extension StringProtocol {
    var trimmed: String { String(self).trimmingCharacters(in: .whitespacesAndNewlines) }
}
