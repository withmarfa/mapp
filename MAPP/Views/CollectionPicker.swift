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
                        Button(collection.title) { library.removeFromCollection(selection, collection.id, undoManager: undoManager) }
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

/// Picks the collection to file the items a window asked for in.
struct CollectionPickerSheet: View {
    @CurrentLibrary private var library
    @Environment(\.dismiss) private var dismiss
    let request: CollectionPickRequest
    @State private var selected: ItemID?
    @State private var filter = ""
    @FocusState private var focus: Field?

    private enum Field { case filter, list }

    var body: some View {
        let collections = shown
        VStack(alignment: .leading, spacing: 12) {
            Text("Add to Collection").interfaceFont(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
            if let skipped = library.collectionPlan(request.ids, joining: nil).skips.message {
                Text(skipped).interfaceFont(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("CollectionPickerSkipped")
            }
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .filter)
                .onKeyPress(.downArrow) {
                    guard !collections.isEmpty else { return .ignored }
                    if selected == nil { selected = firstAddable(in: collections) }
                    focus = .list
                    return .handled
                }
                .onSubmit { add() }
                .accessibilityIdentifier("CollectionPickerFilter")
            List(collections, selection: $selected) { collection in
                HStack {
                    Label(collection.title, systemImage: TypeSymbol.name(for: collection.type, in: library.catalogue))
                    Spacer()
                    if holdsAll(collection.id) { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                }
                .tag(collection.id)
                .selectionDisabled(holdsAll(collection.id))
                .accessibilityIdentifier("CollectionPickerOption.\(collection.id.rawValue)")
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .focused($focus, equals: .list)
            // Return and a double-click both act on the row, as they do in any list.
            .contextMenu(forSelectionType: ItemID.self) { _ in } primaryAction: { ids in
                add(ids.first)
            }
            .onKeyPress(.return) {
                guard selected != nil else { return .ignored }
                add()
                return .handled
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
        .onAppear { focus = .filter }
        // The first collection that can be added to stays selected as the filter narrows the list, so Return adds it.
        .onChange(of: filter) { selected = firstAddable(in: shown) }
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
        !library.collectionMembers(request.ids).isEmpty
    }

    private var subtitle: String {
        if request.ids.count == 1, let item = request.ids.first.flatMap({ library.item($0) }) {
            String(localized: "Choose a collection for “\(item.title)”.")
        } else {
            String(localized: "Choose a collection for \(request.ids.count) items.")
        }
    }

    private func holdsAll(_ collection: ItemID) -> Bool {
        let members = library.collectionMembers(request.ids)
        return !members.isEmpty && members.allSatisfy { library.item($0)?.collectionIDs.contains(collection) == true }
    }

    private func firstAddable(in collections: [Item]) -> ItemID? {
        collections.first { !holdsAll($0.id) }?.id
    }

    private func add(_ id: ItemID? = nil) {
        guard let target = id ?? selected, !holdsAll(target) else { return }
        if library.addToCollection(request.ids, target, undoManager: request.undoManager) { dismiss() }
    }
}
