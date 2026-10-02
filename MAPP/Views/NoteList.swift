import SwiftUI

struct NoteList: View {
    @Environment(NoteLibrary.self) private var library
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
        let files = browser.files(in: library)
        let ids = sections.flatMap { $0.notes.map(\.id) } + files.map(\.id)
        let title = browser.isSearching ? String(localized: "Search") : library.name(of: browser.item)
        // Headings are rows of their own rather than section headers: a list of sections leaves every row at
        // the table's default height, and its first header floats into the toolbar's edge, whose line then runs
        // the list's full width.
        List(selection: $browser.selection) {
            ForEach(ListLine.lines(of: sections)) { line in
                switch line {
                case .heading(let group, let isFirst):
                    Text(group.title())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, isFirst ? 0 : 10)
                        .accessibilityAddTraits(.isHeader)
                        .selectionDisabled()
                        .listRowSeparator(.hidden, edges: .top)
                case .note(let note, let endsSection):
                    NoteRow(
                        note: note,
                        dateLabel: NoteDate.listLabel(for: order.sort.date(of: note), now: now),
                        folderName: browser.showsFolders ? folderName(for: note) : nil,
                        previewLines: previewLines
                    )
                    .draggable(containerItemID: note.id)
                    .listRowSeparator(endsSection ? .hidden : .automatic, edges: .bottom)
                }
            }
            ForEach(files) { file in
                FileListRow(file: file, dateLabel: NoteDate.listLabel(for: file.stored.modified, now: now), previewLines: previewLines)
                    .tag(file.id)
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
        // Return opens the note for writing; a deleted note cannot be written in, so it stays in the list.
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.isEmpty, browser.selection.count == 1,
                  browser.selectedNotes(in: library).first?.isDeleted == false
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
            ids.compactMap { library.note($0) }.map { NoteReference(id: $0.id, markdown: $0.body) }
        }
        .dragContainerSelection(Array(browser.selection))
        .onChange(of: ids) { old, new in
            browser.selection = Browser.selection(browser.selection, keptFrom: old, in: new)
        }
        .contextMenu(forSelectionType: Note.ID.self) { ids in
            if ids.count == 1, let id = ids.first, library.note(id)?.isDeleted == false {
                Button("Rename…", systemImage: "pencil") { browser.renamingNote = id }
                Divider()
            }
            NoteActions(ids: ids, undoManager: undoManager)
        } primaryAction: { ids in
            for path in library.paths(forWindows: ids) { openWindow(value: path) }
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

    private func folderName(for note: Note) -> String {
        note.folderID.flatMap { library.folder($0)?.name } ?? String(localized: "Inbox")
    }
}

/// Laid out as Mail lays out a message, so the date lines up at the trailing edge, and the preview's lines are
/// reserved whether the note fills them or not, keeping every row the same height.
struct NoteRow: View {
    let note: Note
    let dateLabel: String
    let folderName: String?
    let previewLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(dateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if previewLines > 0 {
                Text(note.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(previewLines, reservesSpace: true)
            }
            if let folderName {
                Label(folderName, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A line of the note list: a section's heading, or a note, with where it falls in its section.
private enum ListLine: Identifiable {
    case heading(NoteGroup, isFirst: Bool)
    case note(Note, endsSection: Bool)

    /// A note's line is known by the note, so the list's selection is its notes; a heading takes an identifier
    /// of its own, never selected.
    var id: Note.ID {
        switch self {
        case .heading(let group, _): UUID(stableFrom: "heading:\(group)")
        case .note(let note, _): note.id
        }
    }

    static func lines(of sections: [NoteSection]) -> [ListLine] {
        var lines: [ListLine] = []
        for section in sections {
            if let group = section.group { lines.append(.heading(group, isFirst: lines.isEmpty)) }
            for note in section.notes {
                lines.append(.note(note, endsSection: note.id == section.notes.last?.id))
            }
        }
        return lines
    }
}

/// File rows keep the same title, date and preview rhythm as the existing note list.
struct FileListRow: View {
    let file: AppFile
    let dateLabel: String
    let previewLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(file.title).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                Text(dateLabel).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
            }
            if previewLines > 0 {
                Label(file.contentType.localizedDescription ?? String(localized: "File"), systemImage: file.isImage ? "photo" : "doc")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(previewLines, reservesSpace: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
