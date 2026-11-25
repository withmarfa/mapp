import SwiftUI

/// What a row offers on itself while the pointer is over it, without a menu. Each acts through the calls the menus use
/// (`ItemLibrary.perform`, `deleteAfterSaving`), so a move here asks, toasts and undoes as it does there.
enum RowQuickAction: Hashable {
    case move(ItemMove)
    case delete
}

extension Browser {
    /// The actions the open place puts on the row under the pointer, where the View panel's Quick Actions has them on:
    /// Unarchive in the Archive, Keep in Library from the Feed, and Archive elsewhere, each with Delete.
    var quickActions: [RowQuickAction] {
        guard showsQuickActions else { return [] }
        if listsArchive { return [.move(.unarchive), .delete] }
        return listing.scope == .feed ? [.move(.keep), .move(.archive), .delete] : [.move(.archive), .delete]
    }
}

/// The quick actions of one row: a capsule for a move, a round button for Delete.
struct RowQuickActions: View {
    @CurrentLibrary private var library
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Environment(\.undoManager) private var undoManager
    let id: ItemID
    let actions: [RowQuickAction]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(actions, id: \.self) { action in
                switch action {
                case .move(let move):
                    Button {
                        library.perform(move, on: [id], undoManager: undoManager, details: details)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: move.symbol)
                            Text(move.name)
                        }
                    }
                    .appButton(.secondary, size: .small)
                    .accessibilityIdentifier("RowAction.\(move.name)")
                case .delete:
                    Button("Delete", systemImage: "trash") {
                        library.deleteAfterSaving([id], undoManager: undoManager, asking: details)
                    }
                    .labelStyle(.iconOnly)
                    .appButton(.secondary, size: .small, icon: true)
                    .help("Delete")
                    .accessibilityIdentifier("RowAction.Delete")
                }
            }
        }
        // The table's cell is narrower than the capsule's words, which must not be squeezed out.
        .fixedSize()
    }
}
