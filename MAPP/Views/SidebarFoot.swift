import SwiftUI

/// The offline indicator stays below the scrolling navigation; other status belongs in Library settings.
struct SidebarFoot: View {
    @Environment(MarfaHost.self) private var host: MarfaHost?
    let browser: Browser

    var body: some View {
        VStack(spacing: 0) {
            if let host, host.source != nil {
                SyncStatusReading(host: host) { status in
                    if let note = status.notes.first(where: { $0.kind == .offline }) {
                        syncLine(note)
                    }
                }
            }
        }
    }

    private func syncLine(_ note: SyncStatus.Note) -> some View {
        Button {
            browser.showSettings(.library)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(note.dotColor)
                    .frame(width: 7, height: 7)
                    .frame(width: 20)
                Text(note.line)
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(note.detail)
        .accessibilityLabel(note.line)
        .accessibilityHint(note.detail)
        .accessibilityIdentifier("SyncStatus")
    }

}
