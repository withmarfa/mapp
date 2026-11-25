import SwiftUI

/// What a row offers on itself while the pointer is over it, without a menu. Each acts through the calls the menus use
/// (`ItemLibrary.perform`, `deleteAfterSaving`), so a move here asks, toasts and undoes as it does there.
enum RowQuickAction: Hashable {
    case move(ItemMove)
    case delete
}

extension Browser {
    /// The actions the open place puts on the row under the pointer. The Archive has them; the setting that turns them on
    /// elsewhere (`docs/agreed.md`, Quick Actions) will decide here.
    var quickActions: [RowQuickAction] { listsArchive ? [.move(.unarchive), .delete] : [] }
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
    }
}
