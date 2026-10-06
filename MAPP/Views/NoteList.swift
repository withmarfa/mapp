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
                        folderName: browser.showsFolders ? folderName(for: item) : nil,
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
        .toolbar {
            ColumnSearch(
                isExpanded: $browser.isSearchExpanded,
                text: $browser.searchText,
                prompt: String(localized: "Search"),
                columnWidth: width,
                focusRequests: browser.searchFocusRequests,
                onDown: { browser.focusRequest = .list }
            ) {
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    OrderOptions()
                        .pickerStyle(.inline)
                }
                .menuIndicator(.hidden)
                .help("Sort")
            }
        }
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
            browser.selection = Browser.selection(browser.selection, keptFrom: old, in: new)
        }
        .contextMenu(forSelectionType: ItemID.self) { ids in
            if ids.count == 1, let id = ids.first, library.canRenameFile(of: library.item(id)) {
                Button("Rename…", systemImage: "pencil") { browser.renamingNote = id }
                Divider()
            }
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
        EditorController.flushAll(leaving: false) { [library, undoManager] in
            Browser.delete(ids, in: library, undoManager: undoManager)
        }
    }

    private func folderName(for item: Item) -> String {
        library.folder(of: item)?.name ?? String(localized: "Inbox")
    }
}

/// Laid out as Mail lays out a message, so the date lines up at the trailing edge, and the preview's lines are
/// reserved whether the item fills them or not, keeping every row the same height. A file's kind stands in for
/// the preview a note has.
struct ItemRow: View {
    let item: Item
    let dateLabel: String
    let folderName: String?
    let previewLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .interfaceFont(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(dateLabel)
                    .interfaceFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if previewLines > 0 {
                Group {
                    if case .file(let type, _) = item.content {
                        Label(type.localizedDescription ?? String(localized: "File"), systemImage: type.conforms(to: .image) ? "photo" : "doc")
                    } else {
                        Text(item.preview)
                    }
                }
                .interfaceFont(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(previewLines, reservesSpace: true)
            }
            if let folderName {
                Label(folderName, systemImage: "folder")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
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
        case .heading(let group, _): ItemID(UUID(stableFrom: "heading:\(group)").uuidString)
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
