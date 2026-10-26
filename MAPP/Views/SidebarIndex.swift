import SwiftUI

/// Indexes navigate to the library's collections and the sources of readable items, never synthetic item records.
struct SidebarIndex: View {
    @CurrentLibrary private var library
    let browser: Browser
    let order: NoteOrder
    let showsCreation: Bool

    var body: some View {
        Group {
            if browser.item == .sources {
                if library.sourceCounts.isEmpty {
                    EmptyState("No Sources", detail: "Sources appear here when items identify where they came from.")
                } else {
                    List(library.sourceCounts) { source in
                        destination(source.name, symbol: "antenna.radiowaves.left.and.right", count: source.count, place: .source(source.name))
                    }
                }
            } else {
                let collections = library.collections
                if collections.isEmpty {
                    if library.catalogue.collectionTypes.isEmpty {
                        EmptyState("No Collections", detail: "This library has no collection type.")
                    } else {
                        EmptyState("No Collections", detail: "Collections you make appear here.")
                    }
                } else {
                    List(collections) { collection in
                        destination(
                            collection.title, symbol: TypeSymbol.name(for: collection.type, in: library.catalogue),
                            count: library.count(in: .collection(collection.id)), place: .collection(collection.id))
                    }
                }
            }
        }
        .navigationTitle(library.name(of: browser.item))
        .toolbar {
            if showsCreation {
                ToolbarItem(id: "indexNewItem") {
                    NewItemButton(browser: browser)
                }
                ToolbarSpacer(.flexible)
            }
        }
        .accessibilityIdentifier("SidebarIndex")
    }

    private func destination(_ title: String, symbol: String, count: Int, place: SidebarItem) -> some View {
        Button {
            browser.show(place, in: library, order: order)
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(count, format: .number).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
