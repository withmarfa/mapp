import AppKit
import SwiftUI

struct ItemBoard: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    /// The window's, for the Change Type sheet.
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Bindable var browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var cursor: ItemID?
    @State private var anchor: ItemID?

    var body: some View {
        let items = browser.items(in: library)
        let fields = ItemBoardLayout.availableFields(items: items, catalogue: library.catalogue)
        let field = ItemBoardLayout.selectedField(browser.boardFields[browser.item], available: fields)
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)
        VStack(spacing: 0) {
            if let field {
                board(ItemBoardLayout.lanes(items: items, key: field.key, catalogue: library.catalogue), key: field.key)
            } else if items.isEmpty {
                if browser.isSearching { EmptyState.search(browser.searchText) }
                else { EmptyState("No Items") }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(Text("^[\(items.count) item](inflect: true)"))
        .toolbar(removing: browser.isSearchExpanded ? .title : nil)
        .accessibilityIdentifier("ItemBoard")
        .onChange(of: browser.isSearchExpanded) {
            if !browser.isSearchExpanded { browser.focusRequest = .list }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            if let cursor, !ids.contains(cursor) { self.cursor = nil }
            if let anchor, !ids.contains(anchor) { self.anchor = nil }
        }
    }

    /// Set from the toolbar's View Options (`ItemBoardOptions`).
    private var compact: Bool { browser.compactBoards[browser.item, default: false] }

    private func board(_ lanes: [ItemBoardLane], key: String) -> some View {
        let ids = lanes.flatMap { $0.items.map(\.id) }
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(lanes) { lane in
                        laneView(lane, lanes: lanes, key: key, ids: ids)
                    }
                }
                .padding(20)
            }
            .focusable()
            .focusEffectDisabled()
            .focused(pane, equals: .list)
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: .down) { press in
                guard let next = neighbor(in: lanes, direction: press.key) else { return .ignored }
                select(next, ids: ids, extending: press.modifiers.contains(.shift), toggling: false)
                return .handled
            }
            .onKeyPress(.return) {
                guard browser.selection.count == 1 else { return .ignored }
                browser.openCollectionSelection()
                return .handled
            }
            .onKeyPress(.escape) { browser.selection = []; return .handled }
            .onKeyPress("a", phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                browser.selection = Set(ids)
                return .handled
            }
            .onChange(of: cursor) { if let cursor { proxy.scrollTo(cursor) } }
        }
        .dragContainer(for: BoardItemReference.self) { ids in
            ids.map { BoardItemReference(id: $0) }
        }
        .dragContainerSelection(Array(browser.selection))
    }

    private func laneView(_ lane: ItemBoardLane, lanes: [ItemBoardLane], key: String, ids: [ItemID]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: lane.title)
                    .interfaceFont(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(lane.items.count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ScrollView {
                LazyVStack(spacing: compact ? 8 : 12) {
                    ForEach(lane.items) { item in
                        card(item, lane: lane, lanes: lanes, key: key, ids: ids).id(item.id)
                    }
                    if lane.items.isEmpty {
                        Text("No Items")
                            .interfaceFont(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 84)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
        .frame(width: compact ? 244 : 292)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(lane.title)
        .dropDestination(for: BoardItemReference.self, isEnabled: isDestination(lane.id)) { references, _ in
            move(references.map(\.id), to: lane.id, key: key)
        }
    }

    private func card(_ item: Item, lane: ItemBoardLane, lanes: [ItemBoardLane], key: String, ids: [ItemID]) -> some View {
        Button {
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            select(item.id, ids: ids, extending: modifiers.contains(.shift), toggling: modifiers.contains(.command))
            pane.wrappedValue = .list
        } label: {
            BoardCard(item: item, catalogue: library.catalogue, selected: browser.selection.contains(item.id), compact: compact,
                      invalidValue: lane.id == .invalid ? item.value(of: key).map(ItemValueText.string) : nil)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contentShape(.rect(cornerRadius: 9))
        .simultaneousGesture(TapGesture(count: 2).onEnded { open(item.id) })
        .accessibilityAddTraits(browser.selection.contains(item.id) ? .isSelected : [])
        .accessibilityAction(named: Text("Open")) { open(item.id) }
        .contextMenu {
            Button("Open") { open(item.id) }
            Menu("Move To") {
                ForEach(lanes.filter { isDestination($0.id) }) { target in
                    Button {
                        move([item.id], to: target.id, key: key)
                    } label: {
                        if target.id == lane.id { Label(target.title, systemImage: "checkmark") }
                        else { Text(verbatim: target.title) }
                    }
                    .disabled(ItemBoardLayout.move(item, key: key, to: target.id, catalogue: library.catalogue) == .refused || target.id == lane.id)
                }
            }
            .disabled(!item.isEditable)
            AddTagButton(ids: browser.selection.contains(item.id) ? browser.selection : [item.id], details: details, undoManager: undoManager)
            TypeChangeButton(ids: browser.selection.contains(item.id) ? browser.selection : [item.id], details: details, undoManager: undoManager)
            VersionHistoryButton(ids: [item.id], details: details, undoManager: undoManager)
        }
        .draggable(containerItemID: item.id)
    }

    private func isDestination(_ id: ItemBoardLane.ID) -> Bool {
        switch id { case .option, .missing: true; case .invalid, .notApplicable: false }
    }

    private func move(_ ids: [ItemID], to lane: ItemBoardLane.ID, key: String) {
        let visible = Set(browser.items(in: library).map(\.id))
        let unique = Array(Set(ids)).sorted { $0.rawValue < $1.rawValue }
        guard !unique.isEmpty else { return }
        let changes = unique.compactMap { id -> (ItemID, ItemBoardLayout.Move)? in
            guard visible.contains(id), let item = library.item(id) else { return nil }
            return (id, ItemBoardLayout.move(item, key: key, to: lane, catalogue: library.catalogue))
        }
        guard changes.count == unique.count, !changes.contains(where: { $0.1 == .refused }) else {
            library.notices.tell(String(localized: "Can’t Move Items"), String(localized: "This lane isn’t available for every selected item. Check each item’s type and required fields."))
            return
        }
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        for (id, change) in changes {
            guard case .set(let value) = change else { continue }
            let told = library.notices.told
            guard library.setItemProperty(id, key: key, value: value, undoManager: undoManager) else {
                if library.notices.told == told {
                    library.notices.tell(String(localized: "Can’t Move Items"), String(localized: "A change couldn’t be saved. The board shows the values currently held by the library."))
                }
                return
            }
        }
    }

    private func open(_ id: ItemID) { browser.selection = [id]; browser.openCollectionSelection() }

    private func select(_ id: ItemID, ids: [ItemID], extending: Bool, toggling: Bool) {
        if anchor == nil { anchor = ids.first(where: browser.selection.contains) }
        browser.selection = GallerySelection.selecting(id, among: ids, current: browser.selection, anchor: anchor, extending: extending, toggling: toggling)
        if !extending { anchor = id }
        cursor = id
    }

    private func neighbor(in lanes: [ItemBoardLane], direction: KeyEquivalent) -> ItemID? {
        let current = cursor ?? lanes.flatMap(\.items).first(where: { browser.selection.contains($0.id) })?.id
        guard let column = lanes.firstIndex(where: { $0.items.contains { $0.id == current } }),
              let row = lanes[column].items.firstIndex(where: { $0.id == current }) else {
            return lanes.lazy.flatMap(\.items).first?.id
        }
        if direction == .upArrow || direction == .downArrow {
            let next = row + (direction == .upArrow ? -1 : 1)
            return lanes[column].items.indices.contains(next) ? lanes[column].items[next].id : current
        }
        let step = direction == .leftArrow ? -1 : 1
        var next = column + step
        while lanes.indices.contains(next) {
            if !lanes[next].items.isEmpty { return lanes[next].items[min(row, lanes[next].items.count - 1)].id }
            next += step
        }
        return current
    }
}

private struct BoardCard: View {
    let item: Item
    let catalogue: Catalogue
    let selected: Bool
    let compact: Bool
    let invalidValue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            Text(verbatim: item.title)
                .interfaceFont(.headline)
                .foregroundStyle(.primary)
                .lineLimit(compact ? 2 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !compact, !item.preview.isEmpty {
                Text(verbatim: item.preview)
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack(spacing: 6) {
                Image(systemName: TypeSymbol.name(for: item.type, in: catalogue))
                Text(verbatim: TypeSymbol.label(for: item.type, in: catalogue))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !item.isEditable { Image(systemName: "lock").accessibilityLabel("Read Only") }
            }
            .interfaceFont(.caption)
            .foregroundStyle(.secondary)
            if let invalidValue {
                Text(verbatim: invalidValue)
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(compact ? 11 : 14)
        .background(selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1)
        }
        .accessibilityElement(children: .combine)
    }
}
