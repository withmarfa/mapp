import SwiftUI

struct RecentlyDeletedActions: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    /// The items chosen; any that are not in Recently Deleted are left out.
    let chosen: [Item]

    private var selection: Set<ItemID> { Set(chosen.filter { $0.state == .trashed }.map(\.id)) }

    var body: some View {
        HStack(spacing: 12) {
            if let days = library.trashDays {
                Text("Deleted items are kept for \(days) days.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Restore") { library.recover(selection, undoManager: undoManager) }
                .disabled(selection.isEmpty)
            Button("Delete Permanently…", role: .destructive) { library.notesToPurge = selection }
                .disabled(selection.isEmpty || !library.reachesServer)
            Menu("More", systemImage: "ellipsis") {
                Button("Empty Recently Deleted…", role: .destructive) {
                    library.notesToPurge = Set(library.items(in: .recentlyDeleted).map(\.id))
                }
                .disabled(library.count(in: .recentlyDeleted) == 0 || !library.reachesServer)
            }
            .labelStyle(.iconOnly)
            .menuIndicator(.hidden)
        }
        .padding(12)
        .accessibilityIdentifier("RecentlyDeletedActions")
    }
}
