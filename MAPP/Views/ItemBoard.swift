import AppKit
import MarfaIcons
import SwiftUI

struct ItemBoard: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    /// The window's, for the Change Type panel.
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Bindable var browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var cursor: ItemID?
    @State private var anchor: ItemID?
    @State private var daysSeen = 0
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    /// What each card says, worked out once for each item from its type's look.
    @State private var cardContents = CardContents()

    var body: some View {
        let _ = daysSeen
        let items = browser.filteredItems(in: library)
        let fields = browser.boardFieldChoices(in: library)
        // The lanes are the place's group (`ItemBoardOptions`), so a saved view's group is its lanes.
        let field = ItemBoardLayout.selectedField(browser.boardFieldKey(in: browser.item), available: fields)
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)
        VStack(spacing: 0) {
            if let field {
                let lanes = ItemBoardLayout.lanes(items: items, key: field.key, catalogue: library.catalogue)
                // Decided from the items, not the lanes shown: Hide Empty Groups may have removed every group lane.
                let grouped = ItemBoardLayout.groupsByStatus(items: items, key: field.key, catalogue: library.catalogue)
                // A card leaves off what its lane already says: the field the board is grouped by.
                let list = RowList(
                    mixesTypes: Set(items.map(\.type)).count > 1, date: .look, format: dateFormat,
                    day: Calendar.current.startOfDay(for: library.now()))
                let contents = cardContents.contents(
                    of: items, in: library, choices: browser.lookChoices, list: list, shape: CardShape(leaving: field.key, groupsByStatus: grouped))
                board(browser.hidesEmptyGroups ? lanes.filter { !$0.items.isEmpty } : lanes, key: field.key, grouped: grouped, contents: contents)
            } else if items.isEmpty {
                if browser.isSearching { SearchEmptyState(browser: browser) }
                else { EmptyState("No Items") }
            }
        }
        .searchStatus(browser)
        .filteredEmptyState(browser)
        .navigationTitle(title)
        .navigationSubtitle(Text("^[\(items.count) item](inflect: true)").editedSubtitle(browser.hasViewChanges))
        .toolbar(removing: browser.isSearchExpanded ? .title : nil)
        .accessibilityIdentifier("ItemBoard")
        .onChange(of: browser.isSearchExpanded) {
            if !browser.isSearchExpanded { browser.focusRequest = .list }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            if let cursor, !ids.contains(cursor) { self.cursor = nil }
            if let anchor, !ids.contains(anchor) { self.anchor = nil }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) { daysSeen += 1 }
        }
    }

    /// Set from the toolbar's View Options (`ItemBoardOptions`).
    private var compact: Bool { browser.compactBoards[browser.item, default: false] }

    private func board(_ lanes: [ItemBoardLane], key: String, grouped: Bool, contents: [ItemID: RowContent]) -> some View {
        let ids = lanes.flatMap { $0.items.map(\.id) }
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(lanes) { lane in
                        laneView(lane, lanes: lanes, key: key, grouped: grouped, ids: ids, contents: contents)
                    }
                }
                .padding(20)
            }
            .bandsToolbar()
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
        .dragContainer(for: ItemReference.self) { ids in ids.map(library.dragReference(of:)) }
        .dragsSelection(of: browser)
    }

    private func laneView(
        _ lane: ItemBoardLane, lanes: [ItemBoardLane], key: String, grouped: Bool, ids: [ItemID], contents: [ItemID: RowContent]
    ) -> some View {
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
                        if let content = contents[item.id] {
                            card(item, content: content, lane: lane, lanes: lanes, key: key, grouped: grouped, ids: ids).id(item.id)
                        }
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
        .dropDestination(for: ItemReference.self, isEnabled: isDestination(lane)) { references, _ in
            move(references.map(\.id), to: lane.id, key: key)
        }
    }

    private func card(_ item: Item, content: RowContent, lane: ItemBoardLane, lanes: [ItemBoardLane], key: String, grouped: Bool, ids: [ItemID]) -> some View {
        let invalid = lane.id == .invalid
            ? item.value(of: ItemBoardLayout.invalidValueKey(of: item, key: key, groupsByStatus: grouped, catalogue: library.catalogue)).map(ItemValueText.string)
            : nil
        return BoardCell(
            item: item, browser: browser, content: content, compact: compact, invalidValue: invalid,
            select: { extending, toggling in
                select(item.id, ids: ids, extending: extending, toggling: toggling)
                pane.wrappedValue = .list
            },
            open: { open(item.id) }
        ) { selection in
            Button("Open") { open(item.id) }
            // A card inside the selection acts for all of it, as in the other layouts.
            let acting = selection.contains(item.id) ? selection : [item.id]
            Menu("Move To") {
                ForEach(lanes.filter(isDestination)) { target in
                    Button {
                        move(Array(acting), to: target.id, key: key)
                    } label: {
                        if acting.count == 1, target.id == lane.id { Label(target.title, systemImage: "checkmark") }
                        else { Text(verbatim: target.title) }
                    }
                    .disabled(!acting.contains { id in
                        guard let moving = library.item(id) else { return false }
                        if case .set = ItemBoardLayout.move(moving, key: key, to: target.id, catalogue: library.catalogue) { return true }
                        return false
                    })
                }
            }
            AddTagButton(ids: acting, details: details, undoManager: undoManager)
            TypeChangeButton(ids: acting, details: details, undoManager: undoManager)
            VersionHistoryButton(ids: [item.id], details: details)
        }
    }

    private func isDestination(_ lane: ItemBoardLane) -> Bool {
        guard lane.takesItems else { return false }
        return switch lane.id { case .option, .group, .missing: true; case .invalid, .notApplicable: false }
    }

    private func move(_ ids: [ItemID], to lane: ItemBoardLane.ID, key: String) {
        guard !ids.isEmpty else { return }
        // An item the lane doesn't suit is left where it is and counted, so the rest still move.
        let plan = ItemBoardLayout.movePlan(
            ids, key: key, to: lane, shown: Set(browser.filteredItems(in: library).map(\.id)), in: library)
        var skips = plan.skips
        // One undo step for the whole move.
        undoManager?.beginUndoGrouping()
        var moved = 0
        for change in plan.changes {
            let told = library.notices.told
            if library.setItemProperty(change.id, key: change.key, value: change.value, undoManager: undoManager) {
                moved += 1
            } else if library.notices.told == told {
                skips.skip(.cantChange)
            }
        }
        undoManager?.endUndoGrouping()
        library.tellSkipped(skips, didChange: moved > 0, failing: String(localized: "Can’t Move Items"))
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

/// One card of a board as a control: it answers a click, a double click, the context menu and a drag, and reads the
/// selection itself, so a selection that moves runs the bodies of the cells on show and of no card.
private struct BoardCell<Actions: View>: View {
    let item: Item
    let browser: Browser
    let content: RowContent
    let compact: Bool
    let invalidValue: String?
    let select: (_ extending: Bool, _ toggling: Bool) -> Void
    let open: () -> Void
    @ViewBuilder let menu: (_ selection: Set<ItemID>) -> Actions

    var body: some View {
        let isSelected = browser.selection.contains(item.id)
        Button {
            // SwiftUI Button actions do not expose the click's modifiers; AppKit supplies just that event.
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            select(modifiers.contains(.shift), modifiers.contains(.command))
        } label: {
            BoardCard(item: item, content: content, compact: compact, invalidValue: invalidValue)
                .equatable()
                .overlay { BoardSelection(browser: browser, id: item.id) }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contentShape(.rect(cornerRadius: 9))
        .simultaneousGesture(TapGesture(count: 2).onEnded { open() })
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("Open")) { open() }
        .contextMenu { menu(browser.selection) }
        .draggable(containerItemID: item.id)
    }
}

/// The selected card's fill and edge. It reads the selection itself, so a selection that moves redraws these and no card.
private struct BoardSelection: View {
    let browser: Browser
    let id: ItemID

    var body: some View {
        if browser.selection.contains(id) {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.accentColor.opacity(0.12))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accentColor, lineWidth: 2) }
                .allowsHitTesting(false)
        }
    }
}

/// What a board card says: the title, the line its type's look gives it, and the bottom line (the type where the board
/// mixes types, the status, and two facts), none of it the field the board is grouped by. A compact card is its title
/// alone, with its type's mark where the board mixes types. It takes plain values and compares by them.
private struct BoardCard: View, Equatable {
    let item: Item
    let content: RowContent
    let compact: Bool
    let invalidValue: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.content == rhs.content && lhs.compact == rhs.compact && lhs.invalidValue == rhs.invalidValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if compact, content.mixesTypes {
                    TypeGlyph(id: content.typeIcon)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(content.typeLabel)
                }
                Text(verbatim: content.title)
                    .interfaceFont(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(compact ? 2 : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !item.isEditable { Image(systemName: "lock").interfaceFont(.caption).foregroundStyle(.secondary).accessibilityLabel("Read Only") }
            }
            if !compact {
                if let secondary = content.secondary {
                    Text(verbatim: secondary)
                        .interfaceFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !content.chips.isEmpty || content.more > 0 {
                    ChipLine(content: content)
                }
            }
            if let invalidValue {
                Text(verbatim: invalidValue)
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(compact ? 11 : 14)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}
