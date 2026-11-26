import SwiftUI
import UniformTypeIdentifiers

/// Equatable by browser and order so a window change does not re-run its body. Row traits are set in the `ForEach`, not in the row view.
struct ItemList: View, Equatable {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    let browser: Browser
    let order: ItemOrder
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var daysSeen = 0
    @State private var width = ColumnWidth.list.defaultWidth
    @SceneStorage("sidebarHidden") private var isSidebarHidden = false
    @AppStorage(InterfaceKey.showsSidebarHistory) private var showsSidebarHistory = true
    @AppStorage(ListKey.density) private var settingsDensity = Density.standard
    /// Only watched: a place's density is read from the defaults (`Browser.density`), where another window may change it.
    @AppStorage(PlaceDensities.key) private var placeDensities: Data?
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard

    static func == (a: ItemList, b: ItemList) -> Bool { a.browser === b.browser && a.order == b.order }

    var body: some View {
        let _ = Cost.record(.listBody, since: .now)
        // Reading the counter ties the dates and sections to the day changing, so "Today" moves at midnight.
        let _ = daysSeen
        let now = library.now()
        // Worked out off the main actor for a large place, with the ids and types read here, so the body makes no pass over it.
        Group {
            if let arrangement = browser.readyArrangement(in: library, order: order, now: now) {
                content(arrangement, now: now)
            } else {
                PlaceProgress()
            }
        }
        .toolbar {
            // While the sidebar is hidden its button and Back and Forward lead this column's toolbar.
            ListToolbar(
                browser: browser, columnWidth: width - (isSidebarHidden ? ColumnSearchMetrics.sidebarButtonRoom : 0),
                leadsWithHistory: isSidebarHidden && showsSidebarHistory)
        }
        .onClockChange { daysSeen += 1 }
    }

    private func content(_ arrangement: ListArrangement, now: Date) -> some View {
        // A folded section lists its heading alone.
        let ids = arrangement.shownIDs
        // Only a page of a long list is drawn, and the next as its end comes into view (`Browser.listDrawn`).
        let lines = ListLine.lines(of: arrangement.drawn(browser.listDrawn, countsFolded: false))
        let drawnIDs = lines.compactMap(\.itemID)
        // Each row's content is worked out once for the item as it is and held by the browser, so a change of selection or
        // of one item makes the content of that row alone, and a row's body looks nothing up.
        let _ = placeDensities
        let density = browser.density ?? settingsDensity
        let list = browser.rowList(of: arrangement.types, in: library, order: order, now: now, format: dateFormat, density: density)
        let contents = browser.rowContents.contents(of: lines.compactMap(\.entry), in: library, looks: browser.propertyLooks(in: library), list: list)
        let results = browser.searchResults(in: library)
        let excerpts = results?.excerpts ?? [:]
        let isPending = results?.isPending == true
        let title = browser.pageTitle(in: library)
        // Headings are rows of their own rather than section headers: a list of sections leaves every row at
        // the table's default height, and its first header floats into the toolbar's edge, whose line then runs
        // the list's full width.
        return listContent(
            lines: lines, ids: ids, drawnIDs: drawnIDs, contents: contents, density: density, excerpts: excerpts, title: title,
            nesting: arrangement.nesting)
        .onDeleteCommand(perform: deleteSelection)
        .clearsSeveralOnEscape(browser)
        .quickLooksOnSpace(browser)
        // Delete alone is the Edit menu's; Command-Delete deletes as it does in Mail.
        .onKeyPress(.delete, phases: .down) { press in
            guard press.modifiers.contains(.command), !browser.selection.isEmpty else { return .ignored }
            deleteSelection()
            return .handled
        }
        // AppKit maps Command-Backspace to this text-system command before keyDown reaches SwiftUI.
        .onCommand(#selector(NSResponder.deleteToBeginningOfLine(_:))) {
            if !browser.selection.isEmpty { deleteSelection() }
        }
        // Return opens the item for writing; a deleted item or a file cannot be written in, so it stays in the list.
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.isEmpty, browser.selection.count == 1,
                  browser.selectedItems(in: library).first?.allows(.text) == true
            else { return .ignored }
            browser.focusRequest = .page
            return .handled
        }
        .searchStatus(browser)
        .topRowTable()
        .dragContainer(for: ItemReference.self) { ids in ids.map(library.dragReference(of:)) }
        .dragsSelection(of: browser)
        .onChange(of: ids) { old, new in
            browser.keepSelection(from: old, to: new, isPending: isPending, holds: arrangement.holds)
        }
        .background(ChosenItemDrawn(browser: browser, positions: arrangement.shownPositions))
        .background(ChosenParentsOpen(browser: browser, nestings: arrangement.nestings, made: arrangement.made))
        // An answer that lists what the waiting list listed (nothing, most often) changes no ids.
        .onChange(of: isPending) { _, isPending in
            if !isPending { browser.keepHeldSelection(in: ids, holds: arrangement.holds) }
        }
        .contextMenu(forSelectionType: ItemID.self) { ids in
            ItemRowMenu(browser: browser, ids: ids, undoManager: undoManager)
        } primaryAction: { ids in
            browser.open(ids)
        }
    }

    /// The list and its row traits, apart from `body` so that neither is too long for the compiler to check.
    private func listContent(
        lines: [ListLine], ids: [ItemID], drawnIDs: [ItemID], contents: [ItemID: RowContent], density: Density,
        excerpts: [ItemID: SearchExcerpt], title: String, nesting: [ItemID: ItemNesting.Place]
    ) -> some View {
        SelectableList(browser: browser) {
            // The list reads every line's traits (whether it can be selected, its separators, its drag) each time
            // it updates, as it does on every change of selection, out of sight too. Set here, they come from the
            // line alone; set inside `ListLineRow`, they would have SwiftUI run every row's body to find them.
            ForEach(lines) { line in
                let nest = nesting[line.id]
                let row = ListLineRow(
                    line: line, content: contents[line.id], density: density, excerpt: excerpts[line.id], browser: browser,
                    fold: browser.listShape?.arranged == true ? { browser.toggleGroup($0, in: library) } : nil, nest: nest, order: order)
                .selectionDisabled(line.itemID == nil)
                .listRowSeparator(line.itemID == nil ? .hidden : .automatic, edges: .top)
                .listRowSeparator(line.endsSection || line.drawsMore != nil ? .hidden : .automatic, edges: .bottom)
                if let run = line.drawsMore {
                    row.onAppear { browser.drawMoreOfList(after: run) }
                } else if (nest?.depth ?? 0) > 0 {
                    // A sub-item stays under its parent.
                    row
                } else if !line.isHeading {
                    row.draggable(containerItemID: line.id)
                        .dropsInto(collection: line.collectionID(in: library.catalogue), browser: browser, order: order)
                } else {
                    row
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .softSelection(rows: drawnIDs, hovers: true, inert: Set(lines.indices.filter { lines[$0].itemID == nil })) { browser.selection }
        .remembersScroll(in: browser.listMemory)
        .selectsAll { browser.selection = Set(ids) }
        // While the toolbar re-places its items, the list is briefly measured narrower than its column can be.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 >= 280 { width = $0 } }
        .accessibilityIdentifier("ItemList")
        .accessibilityLabel(title)
        .focused(pane, equals: .list)
        .takesKeyboardOnClick { browser.focusRequest = .list }
    }

    /// What was just typed reaches the item before it goes, since a deleted item takes no edit.
    private func deleteSelection() {
        let ids = browser.selection
        library.deleteAfterSaving(ids, undoManager: undoManager, asking: details)
    }
}

/// Binds the native list's selection to the window.
private struct SelectableList<Content: View>: View {
    @Bindable var browser: Browser
    @ViewBuilder let content: Content

    var body: some View {
        List(selection: $browser.selection) { content }
    }
}

/// A line of the list as a row: a section's heading, or an item.
private struct ListLineRow: View {
    @CurrentLibrary private var library
    let line: ListLine
    let content: RowContent?
    let density: Density
    let excerpt: SearchExcerpt?
    let browser: Browser
    /// Folds or opens a section by its key, where the list's groups fold.
    var fold: ((String) -> Void)?
    /// Where the item stands among its parents, where the list nests it.
    var nest: ItemNesting.Place?
    let order: ItemOrder

    var body: some View {
        switch line {
        case .heading(let group, let isFirst, let isCollapsed):
            HStack(spacing: 4) {
                Text(group.title())
                    .interfaceFont(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                if let fold {
                    Button {
                        fold(group.key)
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(isCollapsed ? "Expand Group" : "Collapse Group")
                    .accessibilityLabel(isCollapsed ? "Expand Group" : "Collapse Group")
                }
            }
            .padding(.top, isFirst ? 0 : 10)
        case .more:
            // Drawn only to come into view, which draws the next page.
            Color.clear.frame(height: 1).accessibilityHidden(true)
        case .item(let item, _, _):
            if let content {
                ItemRow(content: content, density: density, excerpt: excerpt, itemID: line.id)
                    .wantsCounts(of: line.id, content.countQueries, in: library.counts)
                    .hoverQuickActions(for: line.id, actions: browser.quickActions(for: item))
                    .nested(nest) { browser.toggleSubItems(of: line.id, in: library, order: order) }
            }
        }
    }
}

extension View {
    /// A list row under its parent: stood in by its depth, with the chevron of a parent before it (`SubItemDisclosure`).
    /// How many sub-items are done is the type's look's to say, as a progress count, as on a card.
    @ViewBuilder fileprivate func nested(_ nest: ItemNesting.Place?, toggle: @escaping () -> Void) -> some View {
        if let nest {
            HStack(spacing: SubItemDisclosure.gap) {
                SubItemDisclosure(place: nest, toggle: toggle)
                self
            }
            .padding(.leading, CGFloat(nest.depth) * SubItemDisclosure.indent - SubItemDisclosure.width - SubItemDisclosure.gap)
        } else {
            self
        }
    }
}

/// A line of the list: a section's heading, or an item, with where it falls in its section.
private enum ListLine: Identifiable {
    case heading(ItemGroup, isFirst: Bool, isCollapsed: Bool)
    case item(Item, group: ItemGroup?, endsSection: Bool)
    /// The line after a run of a list drawn in part, which draws the next page of the run as it comes into view.
    case more(run: Int)

    /// An item's line is known by the item, so the list's selection is its items; a heading takes an identifier
    /// of its own, never selected.
    var id: ItemID {
        switch self {
        case .heading(let group, _, _): ItemID("heading:\(group)")
        case .item(let item, _, _): item.id
        case .more(let run): ItemID("more:\(run)")
        }
    }

    var isHeading: Bool {
        if case .heading = self { true } else { false }
    }

    /// The run the line draws more of, where it is the line after one.
    var drawsMore: Int? {
        if case .more(let run) = self { run } else { nil }
    }

    /// The item of an item's line.
    var itemID: ItemID? {
        if case .item(let item, _, _) = self { item.id } else { nil }
    }

    /// The item's identity where it is a collection, which items and files dropped on its row join.
    func collectionID(in catalogue: Catalogue) -> ItemID? {
        if case .item(let item, _, _) = self, catalogue.isCollection(item.type) { item.id } else { nil }
    }

    /// The item a line is, and whether its date reads as a time: inside the group of today or yesterday the day is already
    /// said.
    var entry: RowContents.Entry? {
        guard case .item(let item, let group, _) = self else { return nil }
        return RowContents.Entry(item: item, showsTime: group == .today || group == .yesterday)
    }

    var endsSection: Bool {
        if case .item(_, _, let endsSection) = self { endsSection } else { false }
    }

    /// The lines of the parts of a list drawn (`ListArrangement.drawn`), with a `more` line after each run that has items
    /// after it.
    static func lines(of parts: [DrawnSection]) -> [ListLine] {
        var lines: [ListLine] = []
        for part in parts {
            let section = part.section
            if part.part.startsSection, let group = section.group {
                lines.append(.heading(group, isFirst: lines.isEmpty, isCollapsed: section.isCollapsed))
            }
            for item in section.isCollapsed ? [] : section.items {
                lines.append(.item(item, group: section.group, endsSection: item.id == section.items.last?.id))
            }
            if part.part.endsRun { lines.append(.more(run: part.part.run)) }
        }
        return lines
    }
}

#Preview("Rows") {
    let rows: [RowContent] = [
        RowContent(
            title: "Review the findings", date: "9:41 AM", secondary: "Field Research", typeIcon: "lucide:circle-check",
            typeLabel: "Task", mixesTypes: true,
            chips: [
                .type(icon: "lucide:circle-check", label: "Task"), .status(.inProgress, label: "In Progress"),
                .option(label: "High", tone: .red), .person(initials: "MC", name: "Mira Castell"),
            ], more: 1),
        RowContent(
            title: "Field notes", date: "Yesterday", secondary: "Start with what we observed in the kitchen.",
            typeIcon: "lucide:file-text", typeLabel: "Note", mixesTypes: true,
            chips: [.type(icon: "lucide:file-text", label: "Note"), .tag("research")]),
        RowContent(title: "Untitled", date: nil, secondary: nil, typeIcon: "lucide:file-text", typeLabel: "Note", mixesTypes: true),
    ]
    List {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in ItemRow(content: row) }
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in ItemRow(content: row, density: .compact) }
    }
    .listStyle(.inset)
    .interfaceTextStyle()
    .frame(width: 340, height: 460)
}

/// Opens the parents above the chosen items, as the list nests them, so a sub-item chosen by Back, a link or a new item
/// is drawn: when the choice changes, and when the sections it was made in are made again. A view of its own, so the
/// list does not observe the selection.
private struct ChosenParentsOpen: View {
    let browser: Browser
    let nestings: [ItemNesting]
    /// The sections the nestings were made with (`ListArrangement.made`).
    let made: UUID

    var body: some View {
        Color.clear
            .onChange(of: browser.selection, initial: true) { browser.openParents(of: browser.selection, in: nestings) }
            .onChange(of: made) { browser.openParents(of: browser.selection, in: nestings) }
    }
}

/// Tracks the cursor or selection in a separate view so a selection change can extend the page
/// without making the layout observe the selection.
struct ChosenItemDrawn: View {
    let browser: Browser
    /// Where each item of the layout stands, counting from its first, as the layout counts what it draws (`ListDrawn`).
    let positions: [ItemID: Int]
    /// The gallery's keyboard cursor, which a new single choice made elsewhere, such as a link, ends.
    var cursor: Binding<ItemID?>?

    var body: some View {
        let single = browser.selection.count == 1 ? browser.selection.first : nil
        let id = Self.shown(cursor: cursor?.wrappedValue, single: single)
        Color.clear
            .onChange(of: id.flatMap { positions[$0] }, initial: true) { _, position in
                if let position { browser.drawList(showing: position) }
            }
            .onChange(of: single) { _, single in
                if let cursor, Self.endsCursor(cursor.wrappedValue, single: single) { cursor.wrappedValue = nil }
            }
    }

    /// The item to keep drawn: the cursor while it is the single choice or there is none, else the single choice.
    static func shown(cursor: ItemID?, single: ItemID?) -> ItemID? {
        cursor.flatMap { single == nil || single == $0 ? $0 : nil } ?? single
    }

    /// Whether a new single choice made elsewhere, such as a link, ends the cursor.
    static func endsCursor(_ cursor: ItemID?, single: ItemID?) -> Bool {
        guard let cursor, let single else { return false }
        return cursor != single
    }
}
