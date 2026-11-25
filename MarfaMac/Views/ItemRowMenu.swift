import SwiftUI

/// The context menu of a row, a card, a cell or a bar in every layout and in the list, built once so they never
/// differ. `RowMenuEntry.entries` decides the order; a layout adds what only it has through `layoutActions`, such
/// as the board's Move To.
struct ItemRowMenu<LayoutActions: View>: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @AppStorage(ListKey.openItemsIn) private var opening = ItemOpening.standard
    let browser: Browser
    let ids: Set<ItemID>
    let undoManager: UndoManager?
    @ViewBuilder let layoutActions: LayoutActions

    var body: some View {
        Group {
            if !ids.isEmpty {
                let items = ids.compactMap { library.item($0) }
                let inBin = !items.isEmpty && items.allSatisfy { $0.state == .trashed }
                ForEach(Array(RowMenuEntry.entries(opening: opening, inBin: inBin).enumerated()), id: \.offset) { _, entry in
                    view(of: entry, single: items.count == 1 ? items.first : nil, items: items)
                }
            }
        }
        // On macOS a menu item draws its symbol only when the menu asks for it.
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder private func view(of entry: RowMenuEntry, single: Item?, items: [Item]) -> some View {
        switch entry {
        case .open:
            Button("Open", systemImage: "arrow.up.right") { browser.open(ids, as: opening) }
                .disabled(!opening.canOpen(ids.count))
        case .openAs(let way):
            Button(way.commandTitle, systemImage: way.symbol) { browser.open(ids, as: way) }
                .disabled(!way.canOpen(ids.count))
        case .quickLook:
            Button("Quick Look", systemImage: "eye") {
                if browser.selection != ids { browser.selection = ids }
                Task { await browser.quickLookSelection(in: library) }
            }
        case .share:
            ItemShareLink(item: single, fileURL: single.flatMap { browser.fileURL(of: $0.id) }, library: library)
        case .copyLink:
            if let single { Button("Copy Link", systemImage: "link") { Task { await library.copyLink(of: single.id) } } }
        case .favorite: FavoriteButton(ids: ids, undoManager: undoManager, inMenu: true)
        case .tag: AddTagButton(ids: ids, details: details, undoManager: undoManager)
        case .collection: CollectionActions(selection: ids, details: details, undoManager: undoManager)
        case .layoutActions: layoutActions
        case .changeType: TypeChangeButton(ids: ids, details: details, undoManager: undoManager)
        case .versionHistory: VersionHistoryButton(ids: ids, details: details)
        case .moves: ItemMoveActions(ids: ids, undoManager: undoManager, shortcuts: libraries.shortcuts)
        case .recover:
            Button("Recover", systemImage: "arrow.uturn.backward") { library.recover(ids, undoManager: undoManager) }
        case .delete: ItemRemoveActions(ids: ids, undoManager: undoManager, showsDeleteKey: true)
        case .divider: Divider()
        }
    }
}

extension ItemRowMenu where LayoutActions == EmptyView {
    init(browser: Browser, ids: Set<ItemID>, undoManager: UndoManager?) {
        self.init(browser: browser, ids: ids, undoManager: undoManager) { EmptyView() }
    }
}
