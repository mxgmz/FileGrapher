import Foundation
import os

/// Lightweight, zero-dependency logging + crash breadcrumbs for GraphingApp.
///
/// The app previously emitted **nothing** — no `os_log`, no crash file — so a runaway redraw
/// loop that pinned WindowServer at 100% CPU left zero trace (a force-quit produces no `.ips`).
/// This makes incidents diagnosable after the fact.
///
/// Two channels:
///  1. **Unified log** via `os.Logger` (subsystem `com.maxgomez.graphingapp`). Inspect with:
///       log show   --predicate 'subsystem == "com.maxgomez.graphingapp"' --last 30m --info --debug
///       log stream --predicate 'subsystem == "com.maxgomez.graphingapp"' --level debug
///  2. **Crash breadcrumbs** under `~/Library/Logs/GraphingApp/crash-*.log`, written from an
///     uncaught-exception handler and POSIX signal handlers (best effort) so a hard failure
///     leaves something behind.
enum Log {
    static let subsystem = "com.maxgomez.graphingapp"

    /// App lifecycle: launch, terminate, vault open.
    static let app    = Logger(subsystem: subsystem, category: "app")
    /// Canvas / rendering: layout guards, runaway-loop tripwires.
    static let canvas = Logger(subsystem: subsystem, category: "canvas")
    /// Disk mutations: file create/move/delete, board save failures.
    static let disk   = Logger(subsystem: subsystem, category: "disk")
    /// Undo / redo transaction engine.
    static let undo   = Logger(subsystem: subsystem, category: "undo")

    /// Where crash breadcrumbs land. Independent of the (possibly not-yet-chosen) vault.
    static var crashLogDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GraphingApp", isDirectory: true)
    }

    private static var didInstall = false

    /// Install the uncaught-exception + signal handlers. Idempotent; call once at launch.
    static func installCrashHandlers() {
        guard !didInstall else { return }
        didInstall = true
        try? FileManager.default.createDirectory(at: crashLogDir, withIntermediateDirectories: true)

        NSSetUncaughtExceptionHandler { ex in
            let trace = ex.callStackSymbols.joined(separator: "\n")
            Log.app.fault("Uncaught exception \(ex.name.rawValue, privacy: .public): \(ex.reason ?? "", privacy: .public)")
            Log.writeCrash("EXCEPTION \(ex.name.rawValue): \(ex.reason ?? "")\n\n\(trace)")
        }

        // Best effort: these allocate inside a signal context (not strictly async-signal-safe),
        // but for a single-user tool a breadcrumb beats silence. We restore default handling and
        // re-raise so the OS still produces its own report.
        for sig in [SIGSEGV, SIGABRT, SIGILL, SIGTRAP, SIGBUS, SIGFPE] {
            signal(sig) { s in
                let frames = Thread.callStackSymbols.joined(separator: "\n")
                Log.writeCrash("SIGNAL \(s)\n\n\(frames)")
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }

    /// Append a timestamped crash breadcrumb. Best effort; never throws.
    static func writeCrash(_ body: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let file = crashLogDir.appendingPathComponent("crash-\(ts.replacingOccurrences(of: ":", with: "-")).log")
        let text = "[\(ts)] GraphingApp\n\(body)\n"
        try? text.data(using: .utf8)?.write(to: file, options: .atomic)
    }
}
