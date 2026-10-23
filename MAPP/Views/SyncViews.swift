import AppKit
import SwiftUI

/// Reads how the library stands with its server, again as the clock passes: a change made online goes within
/// moments and is not worth a line, so a line about sending waits for the clock.
struct SyncStatusReading<Content: View>: View {
    let host: MarfaHost
    @ViewBuilder let content: (SyncStatus) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: host.report.waiting > 0 ? 1 : 60)) { context in
            content(SyncStatus(state: host.state, report: host.report, now: context.date))
        }
    }
}

extension SyncStatus.Note {
    /// The colour of the dot beside the note: red where the person has to act, orange where something waits,
    /// and quiet while the app is only catching up.
    var dotColor: Color {
        switch kind {
        case .keyRefused, .unavailable: .red
        case .needsAttention, .offline: .orange
        case .catchingUp, .sending: .secondary
        }
    }
}

/// One change that needs the person: what happened, what they wrote, and what they can do about it.
struct SyncProblemRow: View {
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
                .interfaceFont(.headline)
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
