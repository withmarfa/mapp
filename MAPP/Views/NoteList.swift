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
    @AppStorage(ListKey.previewLines) private var previewLines = ListKey.defaultPreviewLines
    @AppStorage(ListKey.showsPictures) private var showsPictures = true
    @AppStorage(ListKey.rowStyle) private var rowStyle = ListRowStyle.standard
    @AppStorage(ListKey.typeStyles) private var typeStyles = ListTypeStyles()
    @AppStorage(ListKey.showsTypeWhenMixed) private var showsType = true
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
        let context = metaContext(for: items)
        // Each type's style, icon and task fields are settled once for the list, so a row looks its type up and does no
        // catalogue work of its own. Passing none for the view's choice is where Edit View's rows will hand theirs.
        let styles: [TypeID: ListRowType] = ListRowType.types(
            of: Set<TypeID>(items.map(\.type)), view: nil, choices: typeStyles, rowStyle: rowStyle, in: library.catalogue)
        let results = browser.searchResults(in: library)
        let excerpts = results?.excerpts ?? [:]
        let isPending = results?.isPending == true
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)
        // Headings are rows of their own rather than section headers: a list of sections leaves every row at
        // the table's default height, and its first header floats into the toolbar's edge, whose line then runs
        // the list's full width.
        listContent(sections: sections, ids: ids, now: now, context: context, styles: styles, excerpts: excerpts, title: title)
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
        sections: [NoteSection], ids: [ItemID], now: Date, context: ItemMeta.Context, styles: [TypeID: ListRowType],
        excerpts: [ItemID: SearchExcerpt], title: String
    ) -> some View {
        SelectableList(browser: browser) {
            // The list reads every line's traits (whether it can be selected, its separators, its drag) each time
            // it updates, as it does on every change of selection, out of sight too. Set here, they come from the
            // line alone; set inside `ListLineRow`, they would have SwiftUI run every row's body to find them.
            ForEach(ListLine.lines(of: sections)) { line in
                let row = lineRow(line, now: now, context: context, styles: styles, excerpt: excerpts[line.id])
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

    private func lineRow(
        _ line: ListLine, now: Date, context: ItemMeta.Context, styles: [TypeID: ListRowType], excerpt: SearchExcerpt?
    ) -> ListLineRow {
        ListLineRow(
            line: line, order: order, now: now, dateFormat: dateFormat, context: context, previewLines: previewLines,
            showsPictures: showsPictures, rowType: Self.rowType(of: line, in: styles, fallback: rowStyle), excerpt: excerpt)
    }

    /// What the list tells its rows about itself; the type chip also waits on the setting that turns it off.
    private func metaContext(for items: [Item]) -> ItemMeta.Context {
        var context = browser.metaContext(for: items)
        context.mixesTypes = context.mixesTypes && showsType
        return context
    }

    private func subtitle(count: Int) -> Text {
        let counted = browser.isSearching ? Text("^[\(count) result](inflect: true)") : Text("^[\(count) item](inflect: true)")
        return counted.editedSubtitle(browser.hasViewChanges)
    }

    private static func rowType(of line: ListLine, in types: [TypeID: ListRowType], fallback: ListRowStyle) -> ListRowType {
        guard let type = line.type, let rowType = types[type] else {
            return ListRowType(style: ListRowStyle.resolve(rowStyle: fallback))
        }
        return rowType
    }

    /// What was just typed reaches the note before it goes, since a deleted note takes no edit.
    private func deleteSelection() {
        let ids = browser.selection
        library.deleteAfterSaving(ids, undoManager: undoManager, asking: details)
    }
}

/// A row in the style its list gives its type. Standard is laid out as Mail lays out a message: the title and, at the
/// trailing edge, the date; under them the text, in as many lines as the list is set to show; then what the item is and
/// where it sits. A row has only the lines it has something to put in, so one without text leaves no gap. The other
/// styles (`ListRows.swift`) read only the fields their items have. A search's row is always laid out as a standard
/// one, since its excerpt is the point.
struct ItemRow: View {
    let item: Item
    let dateLabel: String
    let meta: ItemMeta
    let previewLines: Int
    var style = ListRowStyle.standard
    /// Whether pictures show at all, which the With Pictures style needs on.
    var showsPictures = false
    var typeIcon: String?
    var task: TaskRowFacts?
    var highlight: HighlightRowFacts?
    var person: PersonRowFacts?
    /// The words a search found in the item, in place of its preview.
    var excerpt: SearchExcerpt?

    /// A match in the title is shown in the title itself, since the excerpt would only say it again.
    private var titleExcerpt: SearchExcerpt? {
        guard let excerpt, let name = item.name, !name.isEmpty, excerpt.plainText.trimmingCharacters(in: .whitespaces) == name else { return nil }
        return excerpt
    }

    private var isPicture: Bool {
        if case .file(let type, _) = item.content { type.conforms(to: .image) } else { false }
    }

    var body: some View {
        Group {
            if excerpt != nil {
                standard
            } else {
                switch style {
                case .standard, .withPictures: standard
                case .compact: CompactRow(item: item, dateLabel: dateLabel, typeIcon: typeIcon)
                case .task: TaskRow(item: item, task: task ?? TaskRowFacts(), meta: meta)
                case .highlight: HighlightRow(item: item, facts: highlight ?? HighlightRowFacts(), dateLabel: dateLabel, meta: meta)
                case .person: PersonRow(item: item, facts: person ?? PersonRowFacts(), dateLabel: dateLabel, meta: meta)
                }
            }
        }
        .padding(.vertical, style == .compact && excerpt == nil ? 3 : 6)
        .accessibilityElement(children: .combine)
    }

    private var standard: some View {
        HStack(alignment: .top, spacing: 0) {
            text
            if style.showsPictures, showsPictures, isPicture { RowPicture(item: item) }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Group {
                    if let titleExcerpt {
                        Text(titleExcerpt.attributed())
                    } else {
                        Text(item.displayTitle)
                    }
                }
                .interfaceFont(.body.weight(.semibold))
                .lineLimit(1)
                Spacer(minLength: 8)
                Text(dateLabel)
                    .interfaceFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if let excerpt, titleExcerpt == nil {
                // The match is what the person looked for, so it shows even where previews are off.
                Text(excerpt.attributed())
                    .interfaceFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(max(previewLines, 2))
            } else if previewLines > 0, !item.preview.isEmpty {
                Text(item.preview)
                    .interfaceFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(previewLines)
            }
            if !meta.isEmpty {
                ItemMetaLine(meta: meta)
                    .padding(.top, 1)
            }
        }
    }
}

/// A small preview of an image file at the trailing edge of its row, which the row decides from the item before this is
/// made, so a row with no picture is a standard row from its first frame. It holds its place until the picture is made,
/// so a row does not change height as the list scrolls. Made as a gallery card's is, so the two share a picture's cost.
/// The square stays in the row (at no size once the item is known to have no picture) so the task that makes the picture
/// is never removed with it: a picture that couldn't be made now is asked for again when the row next shows.
private struct RowPicture: View {
    @CurrentLibrary private var library
    @Environment(\.displayScale) private var displayScale
    let item: Item
    @State private var artwork: GalleryArtwork?
    @State private var hasNone = false

    private static let side: CGFloat = 44

    var body: some View {
        let basis = GalleryArtworkCache.basis(of: item, in: library)
        let shown = artwork ?? GalleryArtworkCache.peek(basis, width: Self.side)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        shape.fill(.quinary)
            .frame(width: hasNone ? 0 : Self.side, height: hasNone ? 0 : Self.side)
            .overlay {
                if let shown {
                    Image(decorative: shown.image, scale: 1).resizable().scaledToFill()
                }
            }
            .clipShape(shape)
            .padding(.leading, hasNone ? 0 : 10)
            .accessibilityHidden(true)
            .task(id: basis) {
                switch await GalleryArtworkCache.outcome(for: item, width: Self.side, scale: displayScale, in: library) {
                case .picture(let made):
                    if !Task.isCancelled { (artwork, hasNone) = (made, false) }
                case .none:
                    if !Task.isCancelled { (artwork, hasNone) = (nil, true) }
                case .failed:
                    break
                }
            }
    }
}

/// The pieces that say what an item is, side by side with room between them. A type shows as a small version of the
/// page's type chip, its name in its color; a piece with a symbol keeps the symbol. A long label gives way before the
/// mark does.
struct ItemMetaLine: View {
    let meta: ItemMeta

    var body: some View {
        HStack(spacing: 12) {
            ForEach(meta.pieces) { piece in
                switch piece.icon {
                case .symbol(let name):
                    HStack(spacing: 5) {
                        Image(systemName: name)
                        Text(piece.label).lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                case .type(let id):
                    TypePill(icon: id, label: piece.label)
                }
            }
        }
        .interfaceFont(.caption)
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
    @CurrentLibrary private var library
    let line: ListLine
    let order: NoteOrder
    let now: Date
    let dateFormat: DateFormat
    let context: ItemMeta.Context
    let previewLines: Int
    let showsPictures: Bool
    let rowType: ListRowType
    let excerpt: SearchExcerpt?

    var body: some View {
        switch line {
        case .heading(let group, let isFirst):
            Text(group.title())
                .interfaceFont(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, isFirst ? 0 : 10)
                .accessibilityAddTraits(.isHeader)
        case .item(let item, _):
            let style = rowType.style
            let shown = excerpt == nil ? style : (style == .withPictures ? .withPictures : .standard)
            ItemRow(
                item: item,
                dateLabel: DateDisplay.text(of: order.sort.date(of: item), place: .list, format: dateFormat, now: now),
                meta: ItemMeta.make(for: item, in: library, context: context),
                previewLines: previewLines,
                style: shown,
                showsPictures: showsPictures,
                typeIcon: shown == .compact ? rowType.icon : nil,
                task: shown == .task ? TaskRowFacts.make(for: item, type: rowType, now: now, format: dateFormat) : nil,
                highlight: shown == .highlight ? HighlightRowFacts.make(for: item, in: library) : nil,
                person: shown == .person ? PersonRowFacts.make(for: item) : nil,
                excerpt: excerpt
            )
        }
    }
}

/// A line of the list: a section's heading, or an item, with where it falls in its section.
private enum ListLine: Identifiable {
    case heading(NoteGroup, isFirst: Bool)
    case item(Item, endsSection: Bool)

    /// An item's line is known by the item, so the list's selection is its items; a heading takes an identifier
    /// of its own, never selected.
    var id: ItemID {
        switch self {
        case .heading(let group, _): ItemID("heading:\(group)")
        case .item(let item, _): item.id
        }
    }

    var isHeading: Bool {
        if case .heading = self { true } else { false }
    }

    /// The item's identity where it is a collection, which items and files dropped on its row join.
    func collectionID(in catalogue: Catalogue) -> ItemID? {
        if case .item(let item, _) = self, catalogue.isCollection(item.type) { item.id } else { nil }
    }

    /// The type of the item a line is, for the style its list gives that type.
    var type: TypeID? {
        if case .item(let item, _) = self { item.type } else { nil }
    }

    var endsSection: Bool {
        if case .item(_, let endsSection) = self { endsSection } else { false }
    }

    static func lines(of sections: [NoteSection]) -> [ListLine] {
        var lines: [ListLine] = []
        for section in sections {
            if let group = section.group { lines.append(.heading(group, isFirst: lines.isEmpty)) }
            for item in section.items {
                lines.append(.item(item, endsSection: item.id == section.items.last?.id))
            }
        }
        return lines
    }
}

#Preview("Rows") {
    let now = Date.now
    let rows: [(String, String, String, [ItemMeta.Piece], String)] = [
        ("Review the findings", "Compare the field notes and photographs, then write up what the interviews changed about the plan.", "9:41 AM", [.init(icon: .type("lucide:circle-check"), label: "Task"), .init(icon: .type("lucide:folder"), label: "Field Research")], ""),
        ("Field notes", "Start with what we observed in the kitchen: three quotes, two photos and the measurements.", "Yesterday", [.init(icon: .type("lucide:file-text"), label: "Note")], ""),
        ("Decide on the sync wording", "Two names are in use. Pick one and update the docs and the app together.", "Wednesday", [.init(icon: .type("lucide:signpost"), label: "Decision"), .init(icon: .type("lucide:folder"), label: "Marfa")], ""),
        ("Contract.pdf", "PDF Document, 1.2 MB", "23/09/2026", [.init(icon: .type("lucide:file"), label: "File")], ""),
        ("Untitled", "", "04/09/2026", [], ""),
    ]
    List {
        ForEach(rows, id: \.0) { row in
            ItemRow(
                item: Item(
                    id: ItemID(row.0), type: TypeID("core.note"), title: row.0, titleRule: .firstLine, preview: row.1,
                    version: ItemVersion(1), created: now, modified: now),
                dateLabel: row.2, meta: ItemMeta(pieces: row.3), previewLines: 2)
        }
    }
    .listStyle(.inset)
    .interfaceTextStyle()
    .frame(width: 340, height: 460)
}
