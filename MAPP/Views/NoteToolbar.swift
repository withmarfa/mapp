import SwiftUI

/// Creation, formatting and item actions share the trailing toolbar group.
/// The compact title and New Item stay fixed; the other items can be moved or removed through Customize Toolbar.
/// Every action is also a menu command, since a toolbar can be hidden.
struct NoteToolbar: CustomizableToolbarContent {
    @Environment(NoteLibrary.self) private var library
    /// The main window's browser; nil in a note's own window, which makes no notes.
    let browser: Browser?
    let notes: [Note]
    let editor: EditorController
    let details: DetailsPresentation

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "scrolledTitle") {
            Text(notes.first.flatMap { library.item($0.id)?.title } ?? "")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 220, alignment: .leading)
                .accessibilityIdentifier("ScrolledItemTitle")
        }
        .sharedBackgroundVisibility(.hidden)
        .customizationBehavior(.disabled)
        .hidden(!editor.isHeaderScrolledAway || notes.count != 1 || browser?.isCreatingItem == true || showsTypes)
        ToolbarSpacer(.flexible)

        ToolbarItem(id: "newNote") {
            NewNoteButton(browser: browser)
        }
        .customizationBehavior(.disabled)
        .hidden(browser == nil)
        ToolbarItem(id: "format") {
            FormatMenu(editor: editor, note: editableNote)
        }
        .hidden(showsTypes)
        ToolbarItem(id: "details") {
            Button("Details", systemImage: "info.circle") { details.isPresented.toggle() }
                .help(details.isPresented ? "Hide Details" : "Show Details")
                .disabled((browser?.selection.count ?? notes.count) != 1 || browser?.isCreatingItem == true)
                .accessibilityIdentifier("DetailsToggle")
        }
        .hidden(showsTypes)
        ToolbarItem(id: "more") {
            MoreMenu(
                notes: browser?.isCreatingItem != true && (browser?.selection.count ?? notes.count) == notes.count ? notes : [],
                fileURL: selectedFileURL, browser: browser, editor: editor, editableNote: editableNote
            )
        }
        .hidden(showsTypes)
    }

    /// Marfa Types shows a page, not a note, so the tools for notes step aside.
    private var selectedFileURL: URL? {
        guard browser?.isCreatingItem != true, browser?.selection.count == 1, let id = browser?.selection.first else { return nil }
        return library.fileURL(for: id)
    }

    private var showsTypes: Bool { browser?.showsTypes == true }

    /// The one note shown, when it can be written in; the formatting tools act on nothing else.
    private var editableNote: Note? {
        guard browser?.isCreatingItem != true, (browser?.selection.count ?? notes.count) == 1, notes.count == 1,
              let note = notes.first, !note.isDeleted, editor.hasNote, editor.noteID == note.id else { return nil }
        return note
    }
}

private struct NewNoteButton: View {
    @Environment(NoteLibrary.self) private var library
    let browser: Browser?

    var body: some View {
        Button("New Item", systemImage: "plus") {
            browser?.startItemDraft()
        }
        .help("New Item")
        .accessibilityIdentifier("NewItemToolbar")
        .disabled(browser == nil || !library.isLoaded)
    }
}

/// Text styles and emphasis, as Notes offers them under Aa.
private struct FormatMenu: View {
    let editor: EditorController
    let note: Note?

    var body: some View {
        Menu("Format", systemImage: "textformat") {
            ForEach([Format.title, .heading, .subheading, .body], id: \.self, content: toggle)
            Divider()
            ForEach([Format.bold, .italic, .strikethrough, .code], id: \.self, content: toggle)
            Divider()
            ForEach([Format.bulletList, .orderedList, .checklist], id: \.self, content: toggle)
            Button("Table", systemImage: "tablecells") { editor.apply(.table) }
                // A table is inserted beside another table, never inside one.
                .disabled(editor.caret.inTable)
        }
        .menuIndicator(.hidden)
        .help("Format")
        .accessibilityIdentifier("FormatToolbar")
        .disabled(note == nil)
    }

    private func toggle(_ format: Format) -> some View {
        Toggle(isOn: Binding { format.isActive(in: editor.caret) } set: { _ in editor.apply(format) }) {
            Text(format.title)
        }
    }
}

/// What else can be done to the notes shown, as Notes keeps it under its More button.
private struct MoreMenu: View {
    @Environment(\.undoManager) private var undoManager
    let notes: [Note]
    let fileURL: URL?
    let browser: Browser?
    let editor: EditorController
    let editableNote: Note?

    var body: some View {
        Menu("More", systemImage: "ellipsis") {
            NoteShareLink(note: notes.count == 1 ? notes.first : nil, fileURL: fileURL)
            Button("Add Attachment…", systemImage: "paperclip") { editor.isChoosingImages = true }
                .disabled(editableNote == nil)
            Divider()
            if let browser {
                Button("Rename…", systemImage: "pencil") { browser.renamingNote = notes.first?.id }
                    .disabled(notes.count != 1 || notes.first?.isDeleted != false)
                Divider()
            }
            if !notes.isEmpty {
                NoteActions(ids: Set(notes.map(\.id)), undoManager: undoManager)
            }
        }
        .menuIndicator(.hidden)
        .help("More")
        .accessibilityIdentifier("MoreToolbar")
    }
}

/// Shares a note's markdown as text, the form every destination can take.
struct NoteShareLink: View {
    let note: Note?
    var fileURL: URL? = nil

    var body: some View {
        if let fileURL {
            ShareLink(item: fileURL)
        } else if let note {
            ShareLink(item: note.body, subject: Text(note.title), preview: SharePreview(note.title))
        } else {
            ShareLink(item: "")
                .disabled(true)
        }
    }
}
