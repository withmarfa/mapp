import SwiftUI

/// Add to Collection and Remove from Collection for the selection, files among it, offered while any selected item can
/// be a member of a collection. The commands take every selected item and tell the person which they left alone.
struct CollectionActions: View {
    @CurrentLibrary private var library
    let selection: Set<ItemID>
    let details: DetailsPresentation?
    let undoManager: UndoManager?

    var body: some View {
        let members = library.collectionMembers(selection)
        if !members.isEmpty {
            Button("Add to Collection…", systemImage: "rectangle.stack.badge.plus") {
                details?.collectionPick = CollectionPickRequest(ids: selection, undoManager: undoManager)
            }
            .disabled(details == nil || library.collections.isEmpty)
            let holding = library.collections(holding: members)
            if holding.count > 1 {
                Menu("Remove from Collection", systemImage: "rectangle.stack.badge.minus") {
                    ForEach(holding) { collection in
                        Button(collection.displayTitle) { library.removeFromCollection(selection, collection.id, undoManager: undoManager) }
                    }
                }
            } else if let collection = holding.first {
                Button("Remove from Collection", systemImage: "rectangle.stack.badge.minus") {
                    library.removeFromCollection(selection, collection.id, undoManager: undoManager)
                }
            }
        }
    }
}
