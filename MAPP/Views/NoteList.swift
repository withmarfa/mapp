import SwiftUI
import UniformTypeIdentifiers

/// Equatable by browser and order so a window change does not re-run its body. Row traits are set in the `ForEach`, not in the row view.
struct NoteList: View, Equatable {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    @Environment(\.openWindow) private var openWindow
    let browser: Browser
    let order: NoteOrder
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var daysSeen = 0
    @State private var width = ColumnWidth.list.defaultWidth
    @SceneStorage("sidebarHidden") private var isSidebarHidden = false
    @AppStorage(ListKey.density) private var settingsDensity = Density.standard
    /// Only watched: a place's density is read from the defaults (`Browser.density`), where another window may change it.
    @AppStorage(PlaceDensities.key) private var placeDensities: Data?
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard

    static func == (a: NoteList, b: NoteList) -> Bool { a.browser === b.browser && a.order == b.order }

    var body: some View {
        let _ = Cost.record(.listBody, since: .now)
        // Reading the counter ties the dates and sections to the day changing, so "Today" moves at midnight.
        let _ = daysSeen
        let now = library.now()
        let sections = browser.sections(in: library, order: order, now: now)
        let items: [Item] = sections.flatMap(\.items)
        let ids: [ItemID] = items.map(\.id)
        // Each row's content is worked out once for the item as it is and held by the browser, so a change of selection or
        // of one item makes the content of that row alone, and a row's body looks nothing up.
        let lines = ListLine.lines(of: sections)
        let list = browser.rowList(of: items, in: library, order: order, now: now, format: dateFormat)
        let contents = browser.rowContents.contents(of: lines.compactMap(\.entry), in: library, looks: browser.looks(in: library), list: list)
        let _ = placeDensities
        let density = browser.density ?? settingsDensity
        let results = browser.searchResults(in: library)
        let excerpts = results?.excerpts ?? [:]
        let isPending = results?.isPending == true
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)
        // Headings are rows of their own rather than section headers: a list of sections leaves every row at
        // the table's default height, and its first header floats into the toolbar's edge, whose line then runs
        // the list's full width.
        listContent(lines: lines, ids: ids, contents: contents, density: density, excerpts: excerpts, title: title)
        .onDeleteCommand(perform: deleteSelection)
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
        // Return opens the note for writing; a deleted note or a file cannot be written in, so it stays in the list.
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.isEmpty, browser.selection.count == 1,
                  browser.selectedItems(in: library).first?.isWritable == true
            else { return .ignored }
            browser.focusRequest = .page
            return .handled
        }
        .searchStatus(browser)
        .bandsToolbar()
        .toolbar(id: WindowToolbarLayout.list) {
            // While the sidebar is hidden its button leads this column's toolbar, so the field has that much less room.
            ListToolbar(browser: browser, columnWidth: width - (isSidebarHidden ? ColumnSearchMetrics.sidebarButtonRoom : 0))
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                daysSeen += 1
            }
        }
        .dragContainer(for: ItemReference.self) { ids in ids.map(library.dragReference(of:)) }
        .dragsSelection(of: browser)
        .onChange(of: ids) { old, new in
            browser.keepSelection(from: old, to: new, isPending: isPending)
        }
        // An answer that lists what the waiting list listed (nothing, most often) changes no ids.
        .onChange(of: isPending) { _, isPending in
            if !isPending { browser.keepHeldSelection(in: ids) }
        }
        .contextMenu(forSelectionType: ItemID.self) { ids in
            NoteActions(ids: ids, undoManager: undoManager)
        } primaryAction: { ids in
            ItemWindows.open(library.idsForWindows(ids)) { openWindow(value: $0) }
        }
        .overlay { emptyState(isEmpty: ids.isEmpty) }
        .navigationTitle(title)
        .navigationSubtitle(subtitle(count: ids.count))
        // The search field takes the title's place while it is out.
        .toolbar(removing: browser.isSearchExpanded ? .title : nil)
    }

    /// The list and its row traits, apart from `body` so that neither is too long for the compiler to check.
    private func listContent(
        lines: [ListLine], ids: [ItemID], contents: [ItemID: RowContent], density: Density,
        excerpts: [ItemID: SearchExcerpt], title: String
    ) -> some View {
        SelectableList(browser: browser) {
            // The list reads every line's traits (whether it can be selected, its separators, its drag) each time
            // it updates, as it does on every change of selection, out of sight too. Set here, they come from the
            // line alone; set inside `ListLineRow`, they would have SwiftUI run every row's body to find them.
            ForEach(lines) { line in
                let row = ListLineRow(line: line, content: contents[line.id], density: density, excerpt: excerpts[line.id])
                .selectionDisabled(line.isHeading)
                .listRowSeparator(line.isHeading ? .hidden : .automatic, edges: .top)
                .listRowSeparator(line.endsSection ? .hidden : .automatic, edges: .bottom)
                if !line.isHeading {
                    row.draggable(containerItemID: line.id)
                        .dropsInto(collection: line.collectionID(in: library.catalogue), browser: browser, order: order)
                } else {
                    row
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .softSelection(rows: ids) { browser.selection }
        .remembersScroll(in: browser.listMemory)
        .selectsAll { browser.selection = Set(ids) }
        // While the toolbar re-places its items, the list is briefly measured narrower than its column can be.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 >= 280 { width = $0 } }
        .accessibilityIdentifier("NoteList")
        .accessibilityLabel(title)
        .focused(pane, equals: .list)
        .takesKeyboardOnClick { browser.focusRequest = .list }
    }

    @ViewBuilder private func emptyState(isEmpty: Bool) -> some View {
        if isEmpty {
            if browser.isSearching {
                SearchEmptyState(browser: browser)
            } else {
                EmptyState(browser.item == .files ? "No Files" : "No Items")
            }
        }
    }

    private func subtitle(count: Int) -> Text {
        let counted = browser.isSearching ? Text("^[\(count) result](inflect: true)") : Text("^[\(count) item](inflect: true)")
        return counted.editedSubtitle(browser.hasViewChanges)
    }

    /// What was just typed reaches the note before it goes, since a deleted note takes no edit.
    private func deleteSelection() {
        let ids = browser.selection
        library.deleteAfterSaving(ids, undoManager: undoManager, asking: details)
    }
}

/// The list, apart from the note list's body: a list reads its selection as it is made, so a change of selection
/// runs this body rather than the note list's, which lists every item the place holds, and hands the list the same
/// rows as before, which SwiftUI does not go through again.
private struct SelectableList<Content: View>: View {
    @Bindable var browser: Browser
    @ViewBuilder let content: Content

    var body: some View {
        List(selection: $browser.selection) { content }
    }
}

/// A line of the list as a row: a section's heading, or an item.
private struct ListLineRow: View {
    let line: ListLine
    let content: RowContent?
    let density: Density
    let excerpt: SearchExcerpt?

    var body: some View {
        switch line {
        case .heading(let group, let isFirst):
            Text(group.title())
                .interfaceFont(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, isFirst ? 0 : 10)
                .accessibilityAddTraits(.isHeader)
        case .item:
            if let content { ItemRow(content: content, density: density, excerpt: excerpt) }
        }
    }
}

/// A line of the list: a section's heading, or an item, with where it falls in its section.
private enum ListLine: Identifiable {
    case heading(NoteGroup, isFirst: Bool)
    case item(Item, group: NoteGroup?, endsSection: Bool)

    /// An item's line is known by the item, so the list's selection is its items; a heading takes an identifier
    /// of its own, never selected.
    var id: ItemID {
        switch self {
        case .heading(let group, _): ItemID("heading:\(group)")
        case .item(let item, _, _): item.id
        }
    }

    var isHeading: Bool {
        if case .heading = self { true } else { false }
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

    static func lines(of sections: [NoteSection]) -> [ListLine] {
        var lines: [ListLine] = []
        for section in sections {
            if let group = section.group { lines.append(.heading(group, isFirst: lines.isEmpty)) }
            for item in section.items {
                lines.append(.item(item, group: section.group, endsSection: item.id == section.items.last?.id))
            }
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
                .option(label: "High", tone: .red), .person(initials: "AC", name: "August Cayzer"),
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
