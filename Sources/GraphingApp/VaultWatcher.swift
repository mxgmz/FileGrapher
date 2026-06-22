import Foundation
import CoreServices

/// Watches a vault's directory tree for file changes via FSEvents and reports the changed paths
/// (vault-relative), debounced. The read side of the living canvas: an edit in Obsidian or by an
/// agent fires this, and the app re-reads. Zero-dependency — CoreServices ships with macOS.
///
/// Lifetime owns the FSEvents stream; create one per open vault and release it to stop watching.
final class VaultWatcher {
    private let root: URL
    private let onChange: ([String]) -> Void
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "app.graphing.vaultwatcher")

    // Coalesce the burst of events a single save emits into one callback.
    private var pending = Set<String>()
    private var debounce: DispatchWorkItem?

    init(root: URL, onChange: @escaping ([String]) -> Void) {
        self.root = root
        self.onChange = onChange
        start()
    }

    deinit { stop() }

    private func start() {
        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(rawPaths, to: NSArray.self)
            let changed = (0..<count).compactMap { paths[$0] as? String }
            watcher.collect(changed)
        }
        // UseCFTypes → callback gets a CFArray of CFStrings (so the NSArray bridge below is valid;
        // without it `eventPaths` is a C `char**` and messaging it as an object crashes).
        // FileEvents → per-file paths (not just the parent dir); NoDefer → fire promptly on the first event.
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes
                           | kFSEventStreamCreateFlagFileEvents
                           | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2, flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Accumulate changed paths (on the watcher queue) and debounce a single flush.
    private func collect(_ absolutePaths: [String]) {
        for path in absolutePaths { pending.insert(path) }
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func flush() {
        let batch = pending
        pending.removeAll()
        let base = root.standardizedFileURL.path
        let rels: [String] = batch.compactMap { absolute in
            let std = URL(fileURLWithPath: absolute).standardizedFileURL.path
            guard std.hasPrefix(base) else { return nil }
            var rel = String(std.dropFirst(base.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            return rel.isEmpty ? nil : rel
        }
        guard !rels.isEmpty else { return }
        onChange(rels)
    }
}
