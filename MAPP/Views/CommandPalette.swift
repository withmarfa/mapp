import SwiftUI

/// ⌘K: one field that reaches the window's commands, the places in the sidebar and the notes by title. Arrow
/// keys choose, Return runs, and Escape or a click outside puts it away. It offers only what could be done now,
/// so what it lists is what the menus have enabled.
struct CommandPalette: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openSettings) private var openSettings
    @StoredOrder private var order
    @AppStorage(PageKey.fullWidth) private var fullWidth = PageStyle().fullWidth
    let browser: Browser
    let editor: EditorController
    @State private var query = ""
    @State private var highlighted = 0
    /// Where the keyboard was before the palette took it, and goes back to once the palette is put away.
    @State private var returnFocus: Browser.Pane = .list
    @FocusState private var isFieldFocused: Bool

    private struct Entry: Identifiable {
        let id: String
        let title: String
        var detail: String?
        let systemImage: String
        var shortcut: String?
        let action: () -> Void
    }

    var body: some View {
        let entries = matching(entries)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Commands and Notes", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFieldFocused)
                    .onSubmit { run(entries) }
                    .accessibilityIdentifier("CommandPaletteField")
            }
            .padding(12)
            Divider()
            if entries.isEmpty {
                Text("No Results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(entries.indices, id: \.self) { index in
                                row(entries[index], isHighlighted: index == highlighted)
                                    .id(index)
                                    .onTapGesture { run(entries, at: index) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
                }
            }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onKeyPress(.downArrow) {
            highlighted = min(highlighted + 1, max(entries.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlighted = max(highlighted - 1, 0)
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onChange(of: query) { highlighted = 0 }
        .onAppear {
            returnFocus = editor.isFocused ? .page : .list
            isFieldFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command Palette")
    }

    private func row(_ entry: Entry, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.systemImage)
                .frame(width: 20)
                .foregroundStyle(isHighlighted ? .white : .secondary)
            Text(entry.title)
                .lineLimit(1)
            if let detail = entry.detail {
                Text(detail)
                    .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let shortcut = entry.shortcut {
                Text(shortcut)
                    .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
            }
        }
        .foregroundStyle(isHighlighted ? .white : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.accentColor : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }

    // MARK: Running

    private func run(_ entries: [Entry], at index: Int? = nil) {
        let index = index ?? highlighted
        guard entries.indices.contains(index) else { return }
        close()
        entries[index].action()
    }

    private func close() {
        browser.isShowingPalette = false
        if browser.focusRequest == nil { browser.focusRequest = returnFocus }
    }

    // MARK: What it offers

    private func matching(_ entries: [Entry]) -> [Entry] {
        PaletteMatch.ranked(entries.map(\.title), query).map { entries[$0] }
    }

    /// The commands first, then the places, then the notes, the order in which equally good matches are listed.
    private var entries: [Entry] {
        commands + places + (query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : notes)
    }

    private var commands: [Entry] {
        let selected = browser.selectedNotes(in: library)
        let ids = Set(selected.map(\.id))
        let one = selected.count == 1 ? selected.first : nil
        var entries: [Entry] = []
        func add(_ title: String, _ systemImage: String, _ shortcut: String? = nil, action: @escaping () -> Void) {
            entries.append(Entry(id: "command:" + title, title: title, systemImage: systemImage, shortcut: shortcut, action: action))
        }

        if library.isLoaded {
            add(String(localized: "New Note"), "square.and.pencil", "⌘N") { browser.newNote(in: library, undoManager: undoManager) }
            add(String(localized: "New Folder"), "folder.badge.plus", "⇧⌘N") {
                browser.newFolder(in: library, order: order, undoManager: undoManager)
            }
        }
        add(String(localized: "Search Notes"), "magnifyingglass", "⌘P") { browser.focusRequest = .search }

        if let one, !one.isDeleted {
            for format in [Format.title, .heading, .subheading, .body, .bold, .italic, .strikethrough, .code,
                           .codeBlock, .quote, .bulletList, .orderedList, .checklist, .table]
            where format != .table || !editor.caret.inTable {
                let shortcut = format.shortcut.map { Self.symbols($0.modifiers) + String($0.key).uppercased() }
                add(String(localized: format.title), "textformat", shortcut) { editor.apply(format) }
            }
            add(String(localized: "Rename Note…"), "pencil") { browser.renamingNote = one.id }
        }

        if !selected.isEmpty, selected.allSatisfy(\.isDeleted) {
            add(String(localized: "Recover"), "arrow.uturn.backward") { library.recover(ids, undoManager: undoManager) }
        } else if !selected.isEmpty, !selected.contains(where: \.isDeleted) {
            let allPinned = selected.allSatisfy(\.isPinned)
            add(allPinned ? String(localized: "Unpin Note") : String(localized: "Pin Note"), allPinned ? "pin.slash" : "pin") {
                library.setPinned(ids, !allPinned, undoManager: undoManager)
            }
            if !selected.allSatisfy({ $0.folderID == nil }) {
                add(String(localized: "Move to Inbox"), "tray") { library.move(ids, to: nil, undoManager: undoManager) }
            }
            for folder in library.folders where !selected.allSatisfy({ $0.folderID == folder.id }) {
                add(String(localized: "Move to \(folder.name)"), "folder") { library.move(ids, to: folder.id, undoManager: undoManager) }
            }
            add(String(localized: "Delete Note"), "trash") {
                EditorController.flushAll(leaving: false) { [library, undoManager] in library.delete(ids, undoManager: undoManager) }
            }
        }

        if fullWidth {
            add(String(localized: "Standard Width"), "arrow.left.and.right") { fullWidth = false }
        } else {
            add(String(localized: "Full Width"), "arrow.left.and.right") { fullWidth = true }
        }
        if one != nil, editor.hasNote {
            add(String(localized: "Print…"), "printer", "⇧⌘P") { editor.printNote() }
            add(String(localized: "Export as PDF…"), "doc.richtext") { editor.exportPDF() }
        }
        add(String(localized: "Settings…"), "gear", "⌘,") { openSettings() }
        return entries
    }

    private var places: [Entry] {
        var items: [(SidebarItem, String)] = [(.inbox, "tray"), (.allNotes, "note.text"), (.pinned, "pin")]
        items += library.folders.map { (.folder($0.id), "folder") }
        items.append((.recentlyDeleted, "trash"))
        return items.map { item, systemImage in
            Entry(id: "place:\(item)", title: library.name(of: item), detail: String(localized: "Show"), systemImage: systemImage) {
                browser.show(item, in: library, order: order)
                browser.focusRequest = .list
            }
        }
    }

    /// Notes by title, most recently edited first, each shown where it is.
    private var notes: [Entry] {
        library.notes.filter { !$0.isDeleted }.sorted { $0.modified > $1.modified }.map { note in
            let folder = note.folderID.flatMap { library.folder($0)?.name } ?? String(localized: "Inbox")
            return Entry(id: "note:\(note.id)", title: note.title, detail: folder, systemImage: "note.text") {
                reveal(note)
            }
        }
    }

    /// Selects the note where the list is, or in All Notes if the list does not show it, and opens it for writing.
    private func reveal(_ note: Note) {
        if !browser.notes(in: library).contains(where: { $0.id == note.id }) {
            browser.show(.allNotes, in: library, order: order)
        }
        browser.selection = [note.id]
        browser.focusRequest = .page
    }

    /// Modifier keys as the menus write them.
    private static func symbols(_ modifiers: EventModifiers) -> String {
        (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "")
    }
}
