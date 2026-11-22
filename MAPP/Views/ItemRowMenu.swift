import SwiftUI

/// The context menu of a row, a card, a cell or a bar in every layout and in the list, built once so they never
/// differ. `RowMenuEntry.entries` decides the order; a layout adds what only it has through `layoutActions`, such
/// as the board's Move To.
struct ItemRowMenu<LayoutActions: View>: View {
    @CurrentLibrary private var library
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @AppStorage(ListKey.openItemsIn) private var opening = ItemOpening.standard
    let browser: Browser
    let ids: Set<ItemID>
    let undoManager: UndoManager?
    @ViewBuilder let layoutActions: LayoutActions

    var body: some View {
        if !ids.isEmpty {
            let items = ids.compactMap { library.item($0) }
            let inBin = !items.isEmpty && items.allSatisfy { $0.state == .trashed }
            ForEach(Array(RowMenuEntry.entries(opening: opening, inBin: inBin).enumerated()), id: \.offset) { _, entry in
                view(of: entry, single: items.count == 1 ? items.first : nil, items: items)
            }
        }
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
            ItemShareLink(share: ItemShare(item: single, fileURL: single.flatMap { browser.fileURL(of: $0.id) }, in: library))
        case .favorite: FavoriteButton(ids: ids, undoManager: undoManager)
        case .tag: AddTagButton(ids: ids, details: details, undoManager: undoManager)
        case .collection: CollectionActions(selection: ids, details: details, undoManager: undoManager)
        case .layoutActions: layoutActions
        case .changeType: TypeChangeButton(ids: ids, details: details, undoManager: undoManager)
        case .customizeLayout:
            // A right click on a card with no page open has nothing to arrange.
            if details?.showsPage != false { CustomizeLayoutButton(ids: ids, details: details) }
        case .editLayouts:
            EditLayoutsCommand(types: Self.types(of: items, in: library)) { browser.showLayouts(of: $0) }
        case .versionHistory: VersionHistoryButton(ids: ids, details: details)
        case .recover:
            Button("Recover", systemImage: "arrow.uturn.backward") { library.recover(ids, undoManager: undoManager) }
        case .delete: ItemRemoveActions(ids: ids, undoManager: undoManager)
        case .divider: Divider()
        }
    }
}

extension ItemRowMenu {
    /// The types of the items the menu is for, by name: the pages Edit Layouts… can lead to.
    static func types(of items: [Item], in library: any ItemLibrary) -> [ItemTypeInfo] {
        Set(items.map(\.type)).compactMap { library.catalogue.itemTypes[$0] }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
}

extension ItemRowMenu where LayoutActions == EmptyView {
    init(browser: Browser, ids: Set<ItemID>, undoManager: UndoManager?) {
        self.init(browser: browser, ids: ids, undoManager: undoManager) { EmptyView() }
    }
}
