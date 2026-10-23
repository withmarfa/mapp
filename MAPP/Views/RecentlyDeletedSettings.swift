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
            empty(
                "No Library Is Open",
                description: "Open a library to see what you’ve deleted from it.")
        }
    }

    /// An empty state in the space the page has left, under its title.
    private func empty(_ title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        ContentUnavailableView(title, systemImage: "trash", description: Text(description))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 64)
    }

    @ViewBuilder private func content(_ library: any ItemLibrary, items: [Item]) -> some View {
        if items.isEmpty {
            empty(
                "Nothing Deleted",
                description: "Items you delete appear here before they’re deleted for good.")
                .accessibilityIdentifier("RecentlyDeletedEmpty")
        } else {
            let canPurge = library.capabilities.contains(.purge)
            VStack(spacing: 0) {
                Form {
                    Section {
                        ForEach(items) { item in
                            row(item, library: library, canPurge: canPurge)
                        }
                    } footer: {
                        footer(library, canPurge: canPurge)
                    }
                }
                .settingsForm()
                .accessibilityIdentifier("RecentlyDeletedSettings")
                HStack {
                    Spacer()
                    Button("Empty Recently Deleted…", role: .destructive) {
                        library.notesToPurge = Set(items.map(\.id))
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canPurge)
                    .accessibilityIdentifier("RecentlyDeletedEmptyButton")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder private func footer(_ library: any ItemLibrary, canPurge: Bool) -> some View {
        if !canPurge {
            Text("This library can’t delete items for good right now.")
        } else if let days = library.trashDays {
            Text("Deleted items stay here for \(days) days, then they’re deleted for good.")
        }
    }

    private func row(_ item: Item, library: any ItemLibrary, canPurge: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: TypeSymbol.name(for: item.type))
                .interfaceFont(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
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
            Button("Restore") { restore(item, in: library) }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("RecentlyDeletedRestore")
            Menu {
                Button("Restore") { restore(item, in: library) }
                Divider()
                Button("Delete Permanently", role: .destructive) { library.notesToPurge = [item.id] }
                    .disabled(!canPurge)
                    .accessibilityIdentifier("RecentlyDeletedDelete")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Restore") { restore(item, in: library) }
            Divider()
            Button("Delete Permanently", role: .destructive) { library.notesToPurge = [item.id] }
                .disabled(!canPurge)
        }
        .accessibilityElement(children: .contain)
    }

    private func restore(_ item: Item, in library: any ItemLibrary) {
        library.recover([item.id], undoManager: undoManager)
    }
}
