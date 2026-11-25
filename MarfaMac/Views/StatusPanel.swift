import SwiftUI

/// A status seen in a row, a card or a table cell opens the same panel as the item's page: its words by group, with the
/// type's own to edit. A write goes through the library as the page's does, so an item that cannot be edited is offered
/// none (`StatusPanel.canOpen`) and the panel says why a write is refused.
@MainActor
enum StatusPanel {
    /// Whether `item` has a status its person may change here: the type has one, and the item takes a change to it.
    static func canOpen(_ item: Item, in library: any ItemLibrary) -> Bool {
        guard let status = library.catalogue.itemTypes[item.type]?.statusField else { return false }
        return item.obstacle(toField: status.key) == nil
    }

    /// Opens the panel of `id`'s status under `anchor`, or closes it where it is the one open. Nothing opens for an item the
    /// library no longer holds or that cannot take the change.
    static func open(_ id: ItemID, in library: any ItemLibrary, undoManager: UndoManager?, under anchor: NSView?) {
        guard let anchor, let item = library.item(id), canOpen(item, in: library),
              let status = library.catalogue.itemTypes[item.type]?.statusField else { return }
        var request = ValueEditRequest(kind: .status(status), library: library, item: id, undoManager: undoManager)
        request.write = { value in library.setItemProperty(id, key: status.key, value: value, undoManager: undoManager) }
        ValueEditPresenter.shared.present(request, anchor: anchor)
    }
}

/// A status chip that opens its panel on a click, in the bottom line of a row or a card. It reads no library while it
/// draws, so a change to another item draws no chip.
struct StatusChipButton: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let id: ItemID
    let symbol: StatusSymbol
    let label: String
    var size: ChipSize = .row
    @State private var anchor = ValueEditAnchorBox()

    var body: some View {
        Button {
            StatusPanel.open(id, in: library, undoManager: undoManager, under: anchor.view)
        } label: {
            PageChip(text: label, kind: .status(symbol), size: size)
        }
        .buttonStyle(.plain)
        .background { ValueEditAnchor(box: anchor) }
        .accessibilityLabel(Text("Status"))
        .accessibilityValue(Text(label))
        .accessibilityHint(Text("Opens a panel to change the status"))
    }
}
