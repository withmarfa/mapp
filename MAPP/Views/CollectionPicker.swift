import SwiftUI

/// Add to Collection and Remove from Collection, offered only where every item can be a member of a collection.
struct CollectionActions: View {
    @CurrentLibrary private var library
    let ids: Set<ItemID>
    let details: DetailsPresentation?
    let undoManager: UndoManager?

    var body: some View {
        let items = ids.compactMap { library.item($0) }
        if !items.isEmpty, items.allSatisfy(library.canJoinCollection) {
            Button("Add to Collection…", systemImage: "rectangle.stack.badge.plus") {
                details?.collectionPick = CollectionPickRequest(ids: ids, undoManager: undoManager)
            }
            .disabled(details == nil || library.collections.isEmpty)
            let holding = library.collections(holding: ids)
            if holding.count > 1 {
                Menu("Remove from Collection", systemImage: "rectangle.stack.badge.minus") {
                    ForEach(holding) { collection in
                        Button(collection.title) { library.removeFromCollection(ids, collection.id, undoManager: undoManager) }
                    }
                }
            } else if let collection = holding.first {
                Button("Remove from Collection", systemImage: "rectangle.stack.badge.minus") {
                    library.removeFromCollection(ids, collection.id, undoManager: undoManager)
                }
            }
        }
    }
}

/// Picks the collection to file the items a window asked for in.
struct CollectionPickerSheet: View {
    @CurrentLibrary private var library
    @Environment(\.dismiss) private var dismiss
    let request: CollectionPickRequest
    @State private var selected: ItemID?
    @State private var filter = ""

    var body: some View {
        let collections = shown
        VStack(alignment: .leading, spacing: 12) {
            Text("Add to Collection").interfaceFont(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("CollectionPickerFilter")
            List(collections, selection: $selected) { collection in
                HStack {
                    Label(collection.title, systemImage: TypeSymbol.name(for: collection.type, in: library.catalogue))
                    Spacer()
                    if holdsAll(collection.id) { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                }
                .tag(collection.id)
                .accessibilityIdentifier("CollectionPickerOption.\(collection.id.rawValue)")
            }
            .frame(height: 220)
            .overlay {
                if collections.isEmpty { Text("No Collections").foregroundStyle(.secondary) }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.map(holdsAll) ?? true)
                    .accessibilityIdentifier("CollectionPickerConfirm")
            }
        }
        .padding(20)
        .frame(width: 360)
        // Items that go or can no longer join, as when they are deleted elsewhere, leave nothing to add.
        .onChange(of: canAdd) { if !canAdd { dismiss() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("CollectionPickerSheet")
    }

    private var shown: [Item] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let collections = library.collections
        return query.isEmpty ? collections : collections.filter { $0.title.localizedStandardContains(query) }
    }

    private var canAdd: Bool {
        let items = request.ids.compactMap { library.item($0) }
        return !items.isEmpty && items.allSatisfy(library.canJoinCollection)
    }

    private var subtitle: String {
        if request.ids.count == 1, let item = request.ids.first.flatMap({ library.item($0) }) {
            String(localized: "Choose a collection for “\(item.title)”.")
        } else {
            String(localized: "Choose a collection for \(request.ids.count) items.")
        }
    }

    private func holdsAll(_ collection: ItemID) -> Bool {
        request.ids.allSatisfy { library.item($0)?.collectionIDs.contains(collection) == true }
    }

    private func add() {
        guard let selected, !holdsAll(selected) else { return }
        if library.addToCollection(request.ids, selected, undoManager: request.undoManager) { dismiss() }
    }
}
