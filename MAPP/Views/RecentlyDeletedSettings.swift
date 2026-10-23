import SwiftUI

/// The Recently Deleted page of Settings: the items deleted from the open library, each with Restore and, where
/// the library allows, Delete Permanently, and a button to empty the lot. A library keeps its own deleted items for
/// its own number of days.
struct RecentlyDeletedSettings: View {
    @Environment(\.library) private var library
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if let library {
            content(library, items: library.items(in: .recentlyDeleted))
        } else {
            ContentUnavailableView(
                "No Library Is Open", systemImage: "trash",
                description: Text("Open a library to see what you’ve deleted from it."))
        }
    }

    @ViewBuilder private func content(_ library: any ItemLibrary, items: [Item]) -> some View {
        if items.isEmpty {
            ContentUnavailableView(
                "Nothing Deleted", systemImage: "trash",
                description: Text("Items you delete appear here before they’re deleted for good."))
                .accessibilityIdentifier("RecentlyDeletedEmpty")
        } else {
            let canPurge = library.capabilities.contains(.purge)
            Form {
                Section {
                    ForEach(items) { item in
                        row(item, library: library, canPurge: canPurge)
                    }
                } footer: {
                    if let days = library.trashDays {
                        Text("Deleted items stay here for \(days) days, then they’re deleted for good.")
                    }
                }
                Section {
                    Button("Empty Recently Deleted…", role: .destructive) {
                        library.notesToPurge = Set(items.map(\.id))
                    }
                    .disabled(!canPurge)
                    .accessibilityIdentifier("RecentlyDeletedEmptyButton")
                } footer: {
                    if !canPurge {
                        Text("This library can’t delete items for good right now.")
                    }
                }
            }
            .settingsForm()
            .accessibilityIdentifier("RecentlyDeletedSettings")
        }
    }

    private func row(_ item: Item, library: any ItemLibrary, canPurge: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: TypeSymbol.name(for: item.type))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title.isEmpty ? String(localized: "Untitled") : item.title)
                    .interfaceFont(.body)
                    .lineLimit(1)
                Text("Deleted \((item.trashed ?? item.modified).formatted(.relative(presentation: .named)))")
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Restore") { library.recover([item.id], undoManager: undoManager) }
                .accessibilityIdentifier("RecentlyDeletedRestore")
            Button("Delete Permanently", role: .destructive) { library.notesToPurge = [item.id] }
                .disabled(!canPurge)
                .accessibilityIdentifier("RecentlyDeletedDelete")
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
    }
}
