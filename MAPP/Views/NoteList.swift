import SwiftUI
import UniformTypeIdentifiers

struct NoteList: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Bindable var browser: Browser
    let order: NoteOrder
    var pane: FocusState<Browser.Pane?>.Binding
    @State private var daysSeen = 0
    @State private var width: CGFloat = 340
    @AppStorage(ListKey.previewLines) private var previewLines = ListKey.defaultPreviewLines

    var body: some View {
        // Reading the counter ties the dates and sections to the day changing, so "Today" moves at midnight.
        let _ = daysSeen
        let now = library.now()
        let sections = browser.sections(in: library, order: order, now: now)
        let ids = sections.flatMap { $0.items.map(\.id) }
        let context = browser.metaContext(for: sections.flatMap(\.items))
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)
        // Headings are rows of their own rather than section headers: a list of sections leaves every row at
        // the table's default height, and its first header floats into the toolbar's edge, whose line then runs
        // the list's full width.
        List(selection: $browser.selection) {
            ForEach(ListLine.lines(of: sections)) { line in
                switch line {
                case .heading(let group, let isFirst):
                    Text(group.title())
                        .interfaceFont(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, isFirst ? 0 : 10)
                        .accessibilityAddTraits(.isHeader)
                        .selectionDisabled()
                        .listRowSeparator(.hidden, edges: .top)
                case .item(let item, let endsSection):
                    let row = ItemRow(
                        item: item,
                        dateLabel: NoteDate.listLabel(for: order.sort.date(of: item), now: now),
                        meta: ItemMeta.make(for: item, in: library, context: context),
                        previewLines: previewLines
                    )
                    .listRowSeparator(endsSection ? .hidden : .automatic, edges: .bottom)
                    // A file has no markdown to carry, so only a note is dragged.
                    if item.isFile {
                        row
                    } else {
                        row.draggable(containerItemID: item.id)
                    }
                }
            }
        }
        .listStyle(.inset)
        .softSelection(rows: ids, selection: browser.selection)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityIdentifier("NoteList")
        .accessibilityLabel(title)
        .focused(pane, equals: .list)
        .onDeleteCommand(perform: deleteSelection)
        // Delete alone is the Edit menu's; Command-Delete deletes as it does in Mail.
        .onKeyPress(.delete, phases: .down) { press in
            guard press.modifiers.contains(.command), !browser.selection.isEmpty else { return .ignored }
            deleteSelection()
            return .handled
        }
        // Return opens the note for writing; a deleted note or a file cannot be written in, so it stays in the list.
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.isEmpty, browser.selection.count == 1,
                  browser.selectedItems(in: library).first?.isWritable == true
            else { return .ignored }
            browser.focusRequest = .page
            return .handled
        }
        .toolbar { ListToolbar(browser: browser, columnWidth: width) }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                daysSeen += 1
            }
        }
        .dragContainer(for: NoteReference.self) { ids in
            ids.compactMap { library.body(of: $0) }.map { NoteReference(id: $0.id, markdown: $0.text) }
        }
        .dragContainerSelection(Array(browser.selection))
        .onChange(of: ids) { old, new in
            browser.keepSelection(from: old, to: new)
        }
        .contextMenu(forSelectionType: ItemID.self) { ids in
            NoteActions(ids: ids, undoManager: undoManager)
        } primaryAction: { ids in
            for id in library.idsForWindows(ids) { openWindow(value: id) }
        }
        .overlay {
            if ids.isEmpty {
                if browser.isSearching {
                    ContentUnavailableView.search(text: browser.searchText)
                } else {
                    ContentUnavailableView(browser.item == .files ? "No Files" : "No Items", systemImage: browser.item == .files ? "doc" : "note.text")
                }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(browser.isSearching
            ? Text("^[\(ids.count) result](inflect: true)")
            : Text("^[\(ids.count) item](inflect: true)"))
        // The search field takes the title's place while it is out.
        .toolbar(removing: browser.isSearchExpanded ? .title : nil)
    }

    /// What was just typed reaches the note before it goes, since a deleted note takes no edit.
    private func deleteSelection() {
        let ids = browser.selection
        EditorController.flushAll(leaving: false) { [library, undoManager] kept in
            guard kept else { return }
            Browser.delete(ids, in: library, undoManager: undoManager)
        }
    }
}

/// Laid out as Mail lays out a message: the title and, at the trailing edge, the date; under them the text, in as
/// many lines as the list is set to show; then what the item is and where it sits. A row has only the lines it
/// has something to put in, so one without text leaves no gap.
struct ItemRow: View {
    let item: Item
    let dateLabel: String
    let meta: ItemMeta
    let previewLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title.isEmpty ? String(localized: "Untitled") : item.title)
                    .interfaceFont(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(dateLabel)
                    .interfaceFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if previewLines > 0, !item.preview.isEmpty {
                Text(item.preview)
                    .interfaceFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(previewLines)
            }
            if !meta.isEmpty {
                ItemMetaLine(meta: meta)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// The pieces that say what an item is and where it sits, side by side with room between them.
struct ItemMetaLine: View {
    let meta: ItemMeta

    var body: some View {
        HStack(spacing: 12) {
            ForEach(meta.pieces) { piece in
                Label(piece.label, systemImage: piece.symbol)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
        }
        .interfaceFont(.caption)
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
        ("Review the findings", "Compare the field notes and photographs, then write up what the interviews changed about the plan.", "9:41 AM", [.init(symbol: "checkmark.circle", label: "Task"), .init(symbol: "folder", label: "Field Research")], ""),
        ("Field notes", "Start with what we observed in the kitchen: three quotes, two photos and the measurements.", "Yesterday", [.init(symbol: "doc.text", label: "Note")], ""),
        ("Decide on the sync wording", "Two names are in use. Pick one and update the docs and the app together.", "Wednesday", [.init(symbol: "signpost.right", label: "Decision"), .init(symbol: "folder", label: "Marfa")], ""),
        ("Contract.pdf", "PDF Document, 1.2 MB", "23/09/2026", [.init(symbol: "doc", label: "File")], ""),
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
