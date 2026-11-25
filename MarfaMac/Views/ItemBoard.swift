import AppKit
import MarfaIcons
import SwiftUI

struct ItemBoard: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    /// The window's, for the Change Type panel.
    @Bindable var browser: Browser
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var cursor: ItemID?
    @State private var anchor: ItemID?
    @State private var daysSeen = 0
    /// The lanes in view in the horizontal scroll view, which are the only ones whose cards ask for counts.
    @State private var visibleLanes: Set<ItemBoardLane.ID> = []
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    /// What each card says, worked out once for each item from its type's look.
    @State private var cardContents = CardContents()

    var body: some View {
        let _ = daysSeen
        let items = browser.filteredItems(in: library)
        // The lanes are the place's group (`Browser.boardGrouping`), so a saved view's group is its lanes.
        let lanes = browser.boardLanes(in: library)
        let title = browser.pageTitle(in: library)
        VStack(spacing: 0) {
            if let lanes {
                let shown = browser.shownBoardLanes(lanes)
                let grouped = lanes.byStatusGroups
                // A card leaves off what its lane already says: the field the board is grouped by.
                let list = RowList(
                    mixesTypes: Set(items.map(\.type)).count > 1, date: .look, format: dateFormat,
                    day: Calendar.current.startOfDay(for: library.now()))
                let contents = cardContents.contents(
                    of: items, in: library, looks: browser.propertyLooks(in: library), list: list, shape: CardShape(leaving: lanes.key, groupsByStatus: grouped))
                if shown.isEmpty, !items.isEmpty, lanes.all.contains(where: { !$0.items.isEmpty }) {
                    HiddenGroupsEmptyState()
                } else {
                    board(shown, key: lanes.key, grouped: grouped, contents: contents)
                }
            } else if items.isEmpty {
                if browser.isSearching { SearchEmptyState(browser: browser) }
                else { PlaceEmptyState(browser: browser) }
            }
        }
        .searchStatus(browser)
        .filteredEmptyState(browser)
        .navigationTitle(title)
        .navigationSubtitle(browser.countLine(items.count, in: library).editedSubtitle(browser.hasViewChanges))
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
    private var compact: Bool { browser.compactBoards[browser.shown, default: false] }

    private static let laneGap: CGFloat = 12
    private static let edge: CGFloat = 20

    /// The lanes share the width the window gives them, down to the narrowest a card reads in and up to the widest a
    /// lane of few cards looks well at. More lanes than fit scroll.
    private func laneWidth(count: Int, in width: CGFloat) -> CGFloat {
        let lanes = CGFloat(max(count, 1))
        let share = (width - 2 * Self.edge - Self.laneGap * (lanes - 1)) / lanes
        return min(max(share, compact ? 200 : 236), compact ? 260 : 340)
    }

    private func board(_ lanes: [ItemBoardLane], key: String, grouped: Bool, contents: [ItemID: RowContent]) -> some View {
        let ids = lanes.flatMap { $0.items.map(\.id) }
        return ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Self.laneGap) {
                        ForEach(lanes) { lane in
                            laneView(lane, lanes: lanes, key: key, grouped: grouped, ids: ids, contents: contents)
                                .frame(width: laneWidth(count: lanes.count, in: geometry.size.width))
                                .onScrollVisibilityChange(threshold: 0.01) { visible in
                                    if visible { visibleLanes.insert(lane.id) } else { visibleLanes.remove(lane.id) }
                                }
                        }
                    }
                    .padding(.horizontal, Self.edge)
                    .padding(.bottom, Self.edge)
                    .padding(.top, 8)
                    // The window's own width at least, so a few lanes stay at the left.
                    .frame(minWidth: geometry.size.width, alignment: .leading)
                }
                .bandsToolbar()
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
                browser.openSelection() ? .handled : .ignored
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
            HStack(spacing: 7) {
                if let symbol = lane.symbol { StatusMark(symbol) }
                Text(verbatim: lane.title)
                    .interfaceFont(.body.weight(.semibold))
                    .lineLimit(1)
                Text(lane.items.count, format: .number)
                    .interfaceFont(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ScrollView {
                LazyVStack(spacing: compact ? 8 : 10) {
                    ForEach(lane.items) { item in
                        if let content = contents[item.id] {
                            card(item, content: content, lane: lane, lanes: lanes, key: key, grouped: grouped, ids: ids).id(item.id)
                        }
                    }
                    if lane.items.isEmpty {
                        Text("No Items")
                            .interfaceFont(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 72)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
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
            wantsCounts: visibleLanes.contains(lane.id),
            select: { extending, toggling in
                select(item.id, ids: ids, extending: extending, toggling: toggling)
                pane.wrappedValue = .list
            },
            open: { open(item.id) }
        ) { selection in
            // A card inside the selection acts for all of it, as in the other layouts.
            let acting = selection.contains(item.id) ? selection : [item.id]
            ItemRowMenu(browser: browser, ids: acting, undoManager: undoManager) {
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
            }
        }
    }

    private func isDestination(_ lane: ItemBoardLane) -> Bool {
        guard lane.takesItems else { return false }
        return switch lane.id { case .option, .group, .missing: true; case .invalid, .notApplicable, .key: false }
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

    private func open(_ id: ItemID) { browser.open([id]) }

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
    @CurrentLibrary private var library
    let item: Item
    let browser: Browser
    let content: RowContent
    let compact: Bool
    let invalidValue: String?
    /// Whether the card's lane is in view; a lane scrolled out of view lets its cards' counts go.
    let wantsCounts: Bool
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
        .wantsCounts(of: item.id, wantsCounts ? content.countQueries : [], in: library.counts)
        .contentShape(.rect(cornerRadius: 10))
        .simultaneousGesture(TapGesture(count: 2).onEnded { open() })
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("Open")) { open() }
        .contextMenu { menu(browser.selection) }
        .draggable(containerItemID: item.id)
    }
}

/// The selected card's soft ring: 3 points wide in the grey of a chosen row, touching the card, as the gallery's. It reads the selection itself, so a selection that moves redraws these and no card.
private struct BoardSelection: View {
    let browser: Browser
    let id: ItemID

    var body: some View {
        if browser.selection.contains(id) {
            RoundedRectangle(cornerRadius: 10 + 3)
                .strokeBorder(Color(nsColor: .labelColor).opacity(0.08), lineWidth: 3)
                .padding(-3)
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
        VStack(alignment: .leading, spacing: compact ? 4 : 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if compact, content.mixesTypes {
                    TypeGlyph(id: content.typeIcon)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(content.typeLabel)
                }
                Text(verbatim: content.title)
                    .interfaceFont(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !item.allows(.fields) { Image(systemName: "lock").interfaceFont(.caption).foregroundStyle(.secondary).accessibilityLabel("Read Only") }
            }
            if !compact {
                if let secondary = content.secondary {
                    Text(verbatim: secondary)
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !content.chips.isEmpty || content.more > 0 {
                    ChipLine(content: content)
                        .padding(.top, 4)
                }
            }
            if let invalidValue {
                Text(verbatim: invalidValue)
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, compact ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .accessibilityElement(children: .combine)
    }
}
