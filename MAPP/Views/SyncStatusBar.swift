import AppKit
import SwiftUI

/// How the library stands with its server, at the foot of the sidebar as Mail and Notes keep theirs. It says
/// nothing while everything is in step, and nothing at all while the app reads a folder; otherwise it is one
/// quiet line that opens the details and what can be done about them.
struct SyncStatusBar: View {
    @Environment(MarfaHost.self) private var host: MarfaHost?
    @State private var isPresented = false
    let openSettings: () -> Void

    var body: some View {
        if let host, host.source != nil {
            // A change made online goes within moments and is not worth a line, so the line waits for the clock.
            TimelineView(.periodic(from: .now, by: host.report.waiting > 0 ? 1 : 60)) { context in
                let status = SyncStatus(state: host.state, report: host.report, now: context.date)
                if let note = status.primary {
                    line(note, status: status, host: host)
                }
            }
        }
    }

    private func line(_ note: SyncStatus.Note, status: SyncStatus, host: MarfaHost) -> some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                if note.kind == .catchingUp || note.kind == .sending {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: note.symbol)
                }
                Text(note.title)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .foregroundStyle(note.isWarning ? Color.orange : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(note.detail)
        .accessibilityLabel(note.title)
        .accessibilityHint(note.detail)
        .accessibilityIdentifier("SyncStatus")
        // A popover left presented would open again by itself the next time the line returns.
        .onDisappear { isPresented = false }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            SyncDetails(status: status, problems: host.report.problems, isOnline: host.state == .online) {
                isPresented = false
                openSettings()
            }
        }
    }
}

/// What the status line stands for: how the connection is, and each change that needs the person.
private struct SyncDetails: View {
    let status: SyncStatus
    let problems: [SyncProblemEntry]
    let isOnline: Bool
    let openSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // The list below speaks for the changes that need attention.
                ForEach(status.notes.filter { $0.kind != .needsAttention }) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(note.title, systemImage: note.symbol)
                            .font(.headline)
                            .foregroundStyle(note.isWarning ? Color.orange : Color.primary)
                        Text(note.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if status.pointsToSettings {
                    Button("Open Settings…", action: openSettings)
                        .accessibilityIdentifier("SyncOpenSettings")
                }
                ForEach(problems) { problem in
                    Divider()
                    SyncProblemRow(problem: problem, isOnline: isOnline)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 380)
        .frame(maxHeight: 480)
        .accessibilityIdentifier("SyncDetails")
    }
}

/// One change that needs the person: what happened, what they wrote, and what they can do about it.
private struct SyncProblemRow: View {
    @CurrentLibrary private var library
    @Environment(\.openWindow) private var openWindow
    let problem: SyncProblemEntry
    let isOnline: Bool
    @State private var failed: String?
    @State private var isConfirmingDiscard = false
    @State private var isWorking = false

    private var wording: ProblemWording { ProblemWording(problem) { library.item($0)?.title } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(wording.headline)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(wording.explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(wording.details, id: \.self) { detail in
                Text(detail).foregroundStyle(.secondary)
            }
            if wording.canCopyText {
                Text(problem.copyText)
                    .lineLimit(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary, in: .rect(cornerRadius: 6))
            }
            if wording.original != nil || wording.copy != nil {
                HStack {
                    if let original = wording.original {
                        Button("Open Original") { openWindow(value: original) }
                    }
                    if let copy = wording.copy {
                        Button("Open Copy") { openWindow(value: copy) }
                    }
                }
            }
            HStack {
                ForEach(wording.actions) { action in
                    Button(action.title, role: action.isDestructive ? .destructive : nil) { act(action) }
                        .disabled(isWorking || (action.needsServer && !isOnline))
                        .help(action.needsServer && !isOnline ? Text("This needs the server. Try again when you’re back online.") : Text(""))
                }
                if wording.canCopyText {
                    Button("Copy Text", action: copyText)
                }
            }
            if let failed {
                Text(failed)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .controlSize(.small)
        .confirmationDialog("Discard this change?", isPresented: $isConfirmingDiscard) {
            Button("Discard", role: .destructive) { resolve(.discard) }
        } message: {
            Text("What you wrote is lost unless you copy it first.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SyncProblem")
    }

    private func act(_ action: ProblemWording.Action) {
        // A write that carried text is the only copy of it, so it is confirmed. A copy goes to Recently Deleted.
        if action.action == .discard, wording.canCopyText, wording.copy == nil {
            isConfirmingDiscard = true
        } else {
            resolve(action.action)
        }
    }

    private func resolve(_ action: SyncAction) {
        isWorking = true
        failed = nil
        Task {
            defer { isWorking = false }
            do {
                let done = try await library.resolve(problem.id, by: action)
                if !done { failed = String(localized: "That can’t be done right now.") }
            } catch {
                failed = (error as? SourceFailure)?.message ?? String(localized: "That didn’t work. Try again in a moment.")
            }
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(problem.copyText, forType: .string)
    }
}
