import SwiftUI

/// The toolbar over a note, laid out as Notes lays out its own: New Note leading, the formatting tools in the
/// centre, and Share and a More menu trailing, beside search. Everything but New Note can be moved or removed
/// through Customize Toolbar, and every item is also a menu command, since a toolbar can be hidden.
struct NoteToolbar: CustomizableToolbarContent {
    /// The main window's browser; nil in a note's own window, which makes no notes.
    let browser: Browser?
    let notes: [Note]
    let editor: EditorController

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "newNote", placement: .primaryAction) {
            NewNoteButton(browser: browser)
        }
        .customizationBehavior(.disabled)
        .hidden(browser == nil)

        ToolbarItem(id: "format", placement: .principal) {
            FormatMenu(editor: editor, note: editableNote)
        }
        ToolbarItem(id: "checklist", placement: .principal) {
            FormatButton(format: .checklist, systemImage: "checklist", editor: editor, note: editableNote)
        }
        ToolbarItem(id: "table", placement: .principal) {
            FormatButton(format: .table, systemImage: "tablecells", editor: editor, note: editableNote)
        }
        ToolbarItem(id: "attach", placement: .principal) {
            Button("Attach Image", systemImage: "paperclip") { editor.isChoosingImages = true }
                .help("Attach Image")
                .disabled(editableNote == nil)
        }

        ToolbarItem(id: "share") {
            NoteShareLink(note: notes.count == 1 ? notes.first : nil)
                .help("Share")
        }
        ToolbarItem(id: "more") {
            MoreMenu(notes: notes, browser: browser)
        }
    }

    /// The one note shown, when it can be written in; the formatting tools act on nothing else.
    private var editableNote: Note? {
        guard notes.count == 1, let note = notes.first, !note.isDeleted else { return nil }
        return note
    }
}

private struct NewNoteButton: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    let browser: Browser?

    var body: some View {
        Button("New Note", systemImage: "square.and.pencil") {
            browser?.newNote(in: library, undoManager: undoManager)
        }
        .help("New Note")
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
        }
        .menuIndicator(.hidden)
        .help("Format")
        .disabled(note == nil)
    }

    private func toggle(_ format: Format) -> some View {
        Toggle(isOn: Binding { format.isActive(in: editor.caret) } set: { _ in editor.apply(format) }) {
            Text(format.title)
        }
    }
}

private struct FormatButton: View {
    let format: Format
    let systemImage: String
    let editor: EditorController
    let note: Note?

    var body: some View {
        Button {
            editor.apply(format)
        } label: {
            Label(String(localized: format.title), systemImage: systemImage)
        }
        .help(String(localized: format.title))
        // A table goes in beside a table, not inside one.
        .disabled(note == nil || (format == .table && editor.caret.inTable))
    }
}

/// What else can be done to the notes shown, as Notes keeps it under its More button.
private struct MoreMenu: View {
    @Environment(\.undoManager) private var undoManager
    let notes: [Note]
    let browser: Browser?

    var body: some View {
        Menu("More", systemImage: "ellipsis") {
            if let browser {
                Button("Rename…", systemImage: "pencil") { browser.renamingNote = notes.first?.id }
                    .disabled(notes.count != 1 || notes.first?.isDeleted != false)
                Divider()
            }
            NoteActions(ids: Set(notes.map(\.id)), undoManager: undoManager, inMenuBar: true)
        }
        .menuIndicator(.hidden)
        .help("More")
    }
}

/// Shares a note's markdown as text, the form every destination can take.
struct NoteShareLink: View {
    let note: Note?

    var body: some View {
        if let note {
            ShareLink(item: note.body, subject: Text(note.title), preview: SharePreview(note.title))
        } else {
            ShareLink(item: "")
                .disabled(true)
        }
    }
}
