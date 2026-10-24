import SwiftUI

/// Indexes navigate to existing collections and the sources of readable items, never synthetic item records.
struct SidebarIndex: View {
    @CurrentLibrary private var library
    let browser: Browser
    let order: NoteOrder
    let showsCreation: Bool

    var body: some View {
        Group {
            if browser.item == .sources {
                if library.sourceCounts.isEmpty {
                    ContentUnavailableView("No Sources", systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Sources appear here when items identify where they came from."))
                } else {
                    List(library.sourceCounts) { source in
                        destination(source.name, symbol: "antenna.radiowaves.left.and.right", count: source.count, place: .source(source.name))
                    }
                }
            } else {
                if library.collectionTree.isEmpty {
                    ContentUnavailableView("No Collections", systemImage: "square.stack",
                        description: Text("Items with other items filed under them appear here."))
                } else {
                    List {
                        ForEach(library.collectionTree) { node in
                            destination(node.title, symbol: node.symbol, count: library.count(in: .collection(node.id)), place: .collection(node.id))
                            ForEach(node.children) { child in
                                destination(child.title, symbol: child.symbol, count: library.count(in: .collection(child.id)), place: .collection(child.id))
                                    .padding(.leading, 20)
                            }
                        }
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
