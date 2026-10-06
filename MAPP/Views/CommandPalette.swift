import SwiftUI
import UniformTypeIdentifiers

/// ⌘K: one field that reaches the window's commands, the places in the sidebar and the notes by title. ⌘P: the
/// same field searching the text of every note, each found note shown with the words around what was found.
/// Arrow keys choose, Return runs, and Escape or a click outside puts it away. The commands are only what could
/// be done now, so what it lists is what the menus have enabled.
struct CommandPalette: View {
    @CurrentLibrary private var library
    @FocusedValue(\.detailsPresentation) private var details
    @Environment(\.undoManager) private var undoManager
    @StoredOrder private var order
    @AppStorage(PageKey.fullWidth) private var fullWidth = PageStyle().fullWidth
    let browser: Browser
    let editor: EditorController
    let settings: SettingsPresentation
    let mode: Browser.Palette
    @State private var query = ""
    @State private var highlighted = 0
    /// Where the keyboard was before the palette took it, and goes back to once the palette is put away.
    @State private var returnFocus: Browser.Pane = .list
    @FocusState private var isFieldFocused: Bool

    private struct Entry: Identifiable {
        let id: String
        let title: String
        var detail: String?
        /// The words around what a search found.
        var snippet: String?
        let systemImage: String
        var shortcut: String?
        /// Another interface takes the keyboard itself, so the note should not regain focus first.
        var takesFocus = false
        let action: () -> Void
    }

    var body: some View {
        let entries = matching(entries)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(mode == .search ? "Search Notes" : "Search Commands and Notes", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFieldFocused)
                    .onSubmit { run(entries) }
                    .onExitCommand { close() }
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
        .onAppear { returnFocus = editor.isFocused ? .page : .list }
        // The field takes the keyboard once the palette is in the window; asked any sooner, the list keeps it.
        .defaultFocus($isFieldFocused, true)
        .task {
            try? await Task.sleep(for: .milliseconds(50))
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
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(entry.title)
                        .lineLimit(1)
                    if let detail = entry.detail {
                        Text(detail)
                            .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
                            .lineLimit(1)
                    }
                }
                if let snippet = entry.snippet {
                    Text(snippet)
                        .font(.callout)
                        .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
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
        close(returningFocus: !entries[index].takesFocus)
        entries[index].action()
    }

    private func close(returningFocus: Bool = true) {
        browser.palette = nil
        if returningFocus, browser.focusRequest == nil { browser.focusRequest = returnFocus }
    }

    // MARK: What it offers

    private func matching(_ entries: [Entry]) -> [Entry] {
        // A search's results are already what it found, most recently edited first.
        mode == .search ? entries : PaletteMatch.ranked(entries.map(\.title), query).map { entries[$0] }
    }

    /// The commands first, then the places, then the notes, the order in which equally good matches are listed.
    private var entries: [Entry] {
        if mode == .search { return found }
        return commands + places + (query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : notes)
    }

    /// Items whose text or title has what was typed, or the most recently edited before anything is.
    private var found: [Entry] {
        let isEmpty = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let items = isEmpty ? library.items(in: .allNotes) : library.items(matching: query)
        return items.sorted { $0.modified > $1.modified }.prefix(isEmpty ? 12 : 50).map { item in
            // Found in the title, the item is known by its title, and its preview says more than the title again.
            let inTitle = item.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            let body = isEmpty || inTitle ? nil : library.body(of: item.id)
            let snippet = body.flatMap { NoteText.snippet(of: $0.text, around: query) } ?? item.preview
            return Entry(
                id: "note:\(item.id)", title: item.title, detail: folderName(of: item), snippet: snippet.isEmpty ? nil : snippet,
                systemImage: symbol(for: item)
            ) {
                reveal(item)
            }
        }
    }

    private var commands: [Entry] {
        // The note commands act on notes; a file selected takes none of them.
        let selected = browser.selectedItems(in: library).filter { !$0.isFile }
        let ids = Set(selected.map(\.id))
        let one = browser.selection.count == 1 && selected.count == 1 ? selected.first : nil
        var entries: [Entry] = []
        func add(_ title: String, _ systemImage: String, _ shortcut: String? = nil, action: @escaping () -> Void) {
            entries.append(Entry(id: "command:" + title, title: title, systemImage: systemImage, shortcut: shortcut, action: action))
        }

        if library.isLoaded {
            add(String(localized: "New Item"), "plus", "⌘N") { browser.startItemDraft() }
            if library.capabilities.contains(.importFiles) {
                add(String(localized: "Import Files…"), "square.and.arrow.down") { browser.isImportingFiles = true }
            }
            if !browser.isCreatingItem, browser.selection.count == 1, let details {
                add(details.isPresented ? String(localized: "Hide Details") : String(localized: "Show Details"), "info.circle", "⌥⌘I") { details.isPresented.toggle() }
            }
            if library.capabilities.contains(.folders) {
                add(String(localized: "New Folder"), "folder.badge.plus", "⇧⌘N") {
                    browser.newFolder(in: library, order: order, undoManager: undoManager)
                }
            }
        }
        let search = String(localized: "Search Notes")
        entries.append(Entry(id: "command:" + search, title: search, systemImage: "magnifyingglass", shortcut: "⌘P", takesFocus: true) {
            browser.palette = .search
        })

        if let one, one.isWritable {
            if editor.hasNote, editor.noteID == one.id {
            for format in [Format.title, .heading, .subheading, .body, .bold, .italic, .strikethrough, .code,
                           .codeBlock, .quote, .bulletList, .orderedList, .checklist, .table]
            where format != .table || !editor.caret.inTable {
                let shortcut = format.shortcut.map { Self.symbols($0.modifiers) + String($0.key).uppercased() }
                add(String(localized: format.title), "textformat", shortcut) { editor.apply(format) }
            }
            }
            if library.canRenameFile(of: one) {
                add(String(localized: "Rename Note…"), "pencil") { browser.renamingNote = one.id }
            }
        }

        if !selected.isEmpty, selected.allSatisfy({ $0.state == .trashed }) {
            add(String(localized: "Recover"), "arrow.uturn.backward") { library.recover(ids, undoManager: undoManager) }
        } else if !selected.isEmpty, !selected.contains(where: { $0.state == .trashed }) {
            let allFavorites = selected.allSatisfy(\.isFavorite)
            add(allFavorites ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"), allFavorites ? "star.slash" : "star") {
                library.setFavorite(ids, !allFavorites, undoManager: undoManager)
            }
            if library.capabilities.contains(.move) {
                if !selected.allSatisfy({ $0.container == nil }) {
                    add(String(localized: "Move to Inbox"), "tray") { library.move(ids, to: nil, undoManager: undoManager) }
                }
                for folder in library.folders where !selected.allSatisfy({ $0.container == ContainerID(folder.id) }) {
                    add(String(localized: "Move to \(folder.name)"), "folder") { library.move(ids, to: folder.id, undoManager: undoManager) }
                }
            }
            add(String(localized: "Delete Note"), "trash") {
                library.deleteAfterSaving(ids, undoManager: undoManager)
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
        let settingsTitle = String(localized: "Settings…")
        entries.append(Entry(id: "command:" + settingsTitle, title: settingsTitle, systemImage: "gear", shortcut: "⌘,", takesFocus: true) {
            settings.show()
        })
        return entries
    }

    private var places: [Entry] {
        var items: [(SidebarItem, String)] = [(.inbox, "tray"), (.allNotes, "note.text"), (.favorites, "star")]
        items += library.items(in: .itemType("aic.project")).map { (.project($0.id), "square.stack") }
        items += WorkbenchSchema.types.map { (.itemType($0.id), "doc.text") }
        items += [(.files, "doc")]
        items += library.folders.map { (.folder($0.id), "folder") }
        items += [(.recentlyDeleted, "trash"), (.marfaTypes, "cube")]
        return items.map { item, systemImage in
            Entry(id: "place:\(item)", title: library.name(of: item), detail: String(localized: "Show"), systemImage: systemImage) {
                browser.show(item, in: library, order: order)
                browser.focusRequest = .list
            }
        }
    }

    /// Items by title, most recently edited first, each shown where it is.
    private var notes: [Entry] {
        library.items(in: .allNotes).sorted { $0.modified > $1.modified }.map { item in
            Entry(id: "note:\(item.id)", title: item.title, detail: folderName(of: item), systemImage: symbol(for: item)) {
                reveal(item)
            }
        }
    }

    private func folderName(of item: Item) -> String {
        library.folder(of: item)?.name ?? String(localized: "Inbox")
    }

    private func symbol(for item: Item) -> String {
        guard case .file(let type, _) = item.content else { return "note.text" }
        return type.conforms(to: .image) ? "photo" : "doc"
    }

    /// Selects the item where the list is, or in All Notes if the list does not show it, and opens a note for
    /// writing.
    private func reveal(_ item: Item) {
        if !browser.items(in: library).contains(where: { $0.id == item.id }) {
            browser.show(.allNotes, in: library, order: order)
        }
        browser.selection = [item.id]
        browser.focusRequest = item.isFile ? .list : .page
    }

    /// Modifier keys as the menus write them.
    private static func symbols(_ modifiers: EventModifiers) -> String {
        (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "")
    }
}
