import SwiftUI

/// The Version History panel (P0 of Living Canvas git time-travel): opt in to tracking the vault's
/// history, take a manual Snapshot, and read the commit list. **View-only** — nothing here restores
/// or overwrites the working tree; it proves the history data flows before the canvas learns to scrub
/// through it. Opens from the clock button in the top bar.
struct VersionHistoryView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.versionHistoryEnabled {
                commitList
            } else {
                enablePane
            }
        }
        .frame(width: 320, height: 380)
        .onAppear { model.refreshVersionHistory() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.tint)
            Text("Version History").font(.headline)
            Spacer()
            if model.gitBusy { ProgressView().controlSize(.small) }
        }
        .padding(12)
    }

    /// Shown when the vault is not yet a git repo: explain and offer the opt-in.
    private var enablePane: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 40)).foregroundStyle(.tint)
            Text("Track this vault's history")
                .font(.title3.weight(.semibold))
            Text("Turns the vault into a git repository so you can snapshot it and (soon) scrub back through past states. Your files are never modified — history is read-only. The .graphingapp layout sidecar stays out of history.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { model.enableVersionHistory() } label: {
                Label("Enable Version History", systemImage: "checkmark.seal").padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.gitBusy)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    /// Shown once enabled: a Snapshot control + the read-only commit history.
    private var commitList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(workingTreeStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.snapshot() } label: { Label("Snapshot", systemImage: "camera") }
                    .controlSize(.small)
                    .disabled(model.gitBusy || model.uncommittedCount == 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            if model.branches.count > 1 { Divider(); branchRow }
            Divider()
            if model.commits.isEmpty {
                Spacer()
                Text("No commits yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.commits) { commit in
                            CommitRow(commit: commit)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var workingTreeStatus: String {
        let count = model.uncommittedCount
        if count == 0 { return "Working tree clean" }
        return "\(count) uncommitted change\(count == 1 ? "" : "s")"
    }

    /// Pick a branch to preview as a ghost overlay (P3); the current branch entry exits the preview.
    private var branchRow: some View {
        HStack(spacing: 6) {
            Text("Preview branch").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button { model.previewBranch(nil) } label: {
                    Label("\(model.currentBranch) (current)",
                          systemImage: model.previewedBranch == nil ? "checkmark" : "circle")
                }
                ForEach(model.branches.filter { $0 != model.currentBranch }, id: \.self) { branch in
                    Button { model.previewBranch(branch) } label: {
                        Label(branch, systemImage: model.previewedBranch == branch ? "checkmark" : "circle")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(model.previewedBranch ?? model.currentBranch).lineLimit(1)
                }
                .foregroundStyle(model.previewedBranch != nil ? .purple : .primary)
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

/// Bottom strip for git time-travel. Normally a commit scrubber (P1): the right end is the live working
/// tree; dragging the knob left moves back through history (HEAD, then older), rendering that commit's
/// content in cards/peeks. While previewing a branch (P3) it instead shows a branch banner with Exit.
/// Box positions never move and disk is never written — VIEW-ONLY. Shown when previewing a branch, or when
/// version history is enabled with at least one commit.
struct CommitScrubber: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if shouldShow {
            content
                .padding(.horizontal, 16).padding(.vertical, 11)
                .frame(maxWidth: 560)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.22)))
                .shadow(color: .black.opacity(0.14), radius: 7, y: 2)
                .padding(.bottom, 16).padding(.horizontal, 16)
        }
    }

    /// Visible while previewing a branch, or when there's a commit history to scrub.
    private var shouldShow: Bool {
        model.previewedBranch != nil || (model.versionHistoryEnabled && !model.commits.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        if model.previewedBranch != nil {
            branchBanner   // branch preview replaces the commit track (a different axis than history)
        } else {
            VStack(spacing: 7) { label; track }
        }
    }

    private var branchBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(.purple)
            Text("Previewing branch").font(.caption).foregroundStyle(.secondary)
            Text("'\(model.previewedBranch ?? "")'").font(.caption.bold())
            Text("· only-on-branch files show as ghosts")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            if model.gitBusy { ProgressView().controlSize(.small) }
            Button("Exit") { model.previewBranch(nil) }.controlSize(.small).buttonStyle(.borderless)
        }
    }

    /// The commit currently being viewed (nil when live).
    private var current: GitService.Commit? {
        guard let hash = model.viewedCommit else { return nil }
        return model.commits.first { $0.hash == hash }
    }

    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isTimeTraveling ? "clock.arrow.circlepath" : "dot.radiowaves.left.and.right")
                .foregroundStyle(model.isTimeTraveling ? .orange : .green)
            if let current {
                Text(current.shortHash).font(.system(.caption, design: .monospaced)).foregroundStyle(.tint)
                Text(current.subject).font(.caption).lineLimit(1)
                Text("· \(current.relativeDate)").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Live — working tree").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if model.gitBusy { ProgressView().controlSize(.small) }
            if model.isTimeTraveling {
                Button("Back to Live") { model.viewCommit(nil) }
                    .controlSize(.small).buttonStyle(.borderless)
            }
        }
    }

    /// A horizontal track with one stop per commit plus a rightmost "live" stop; the knob marks the
    /// viewed position. Tap or drag anywhere on the track snaps to the nearest stop.
    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let selected = selectedStop
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.22)).frame(height: 4)
                Capsule().fill(Color.accentColor.opacity(0.55))
                    .frame(width: knobX(selected, width), height: 4)
                ForEach(0...model.commits.count, id: \.self) { stop in
                    let isKnob = stop == selected
                    Circle()
                        .fill(isKnob ? Color.accentColor : .secondary.opacity(0.45))
                        .frame(width: isKnob ? 12 : 6, height: isKnob ? 12 : 6)
                        .offset(x: knobX(stop, width) - (isKnob ? 6 : 3))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { select(nearestStop(to: $0.location.x, width: width)) }
            )
        }
        .frame(height: 16)
    }

    // MARK: Stop math — stop 0 = oldest commit … stop `count` = live (rightmost)

    /// Pixel x of a stop's center along a track of the given width.
    private func knobX(_ stop: Int, _ width: CGFloat) -> CGFloat {
        let count = max(model.commits.count, 1)
        return width * CGFloat(stop) / CGFloat(count)
    }

    private func nearestStop(to px: CGFloat, width: CGFloat) -> Int {
        let count = max(model.commits.count, 1)
        let raw = (px / max(width, 1)) * CGFloat(count)
        return min(max(Int(raw.rounded()), 0), model.commits.count)
    }

    private var selectedStop: Int {
        let count = model.commits.count
        guard let hash = model.viewedCommit,
              let index = model.commits.firstIndex(where: { $0.hash == hash }) else { return count }
        return count - 1 - index
    }

    /// Apply a stop selection: the rightmost stop is live; others map to `commits` (newest-first).
    private func select(_ stop: Int) {
        let count = model.commits.count
        model.viewCommit(stop >= count ? nil : model.commits[count - 1 - stop].hash)
    }
}

/// One commit row: subject over short-hash · author · relative date.
private struct CommitRow: View {
    let commit: GitService.Commit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(commit.subject).font(.callout).lineLimit(2)
            HStack(spacing: 6) {
                Text(commit.shortHash)
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tint)
                Text(commit.author).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(commit.relativeDate).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
