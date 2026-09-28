import AppKit
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
        ToolbarItem(id: "newNote") {
            NewNoteButton(browser: browser)
        }
        .customizationBehavior(.disabled)
        .hidden(browser == nil)
        ToolbarSpacer(.flexible)

        ToolbarItem(id: "format") {
            FormatMenu(editor: editor, note: editableNote)
        }
        .hidden(showsTypes)
        ToolbarItem(id: "checklist") {
            FormatButton(format: .checklist, systemImage: "checklist", editor: editor, note: editableNote)
        }
        .hidden(showsTypes)
        ToolbarItem(id: "table") {
            FormatButton(format: .table, systemImage: "tablecells", editor: editor, note: editableNote)
        }
        .hidden(showsTypes)
        ToolbarItem(id: "attach") {
            Button("Attach Image", systemImage: "paperclip") { editor.isChoosingImages = true }
                .help("Attach Image")
                .disabled(editableNote == nil)
        }
        .hidden(showsTypes)

        ToolbarSpacer(.flexible)
        ToolbarItem(id: "share") {
            NoteShareLink(note: notes.count == 1 ? notes.first : nil)
                .help("Share")
        }
        .hidden(showsTypes)
        ToolbarItem(id: "more") {
            MoreMenu(notes: notes, browser: browser)
        }
        .hidden(showsTypes)
    }

    /// Marfa Types shows a page, not a note, so the tools for notes step aside.
    private var showsTypes: Bool { browser?.showsTypes == true }

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

/// Keeps Share and More beside search, as Notes and Mail set them. SwiftUI puts a flexible space of its own before
/// the search field, which would leave them floating between the formatting tools and search; that space goes,
/// as a person could take it out in Customize Toolbar. Only a space that follows the note's own trailing items is
/// taken, so a toolbar with nothing before search, such as Marfa Types', keeps search at its end.
struct SearchBesideTrailingItems: NSViewRepresentable {
    func makeNSView(context: Context) -> Watcher { Watcher() }
    func updateNSView(_ view: Watcher, context: Context) {}

    final class Watcher: NSView {
        private static let trailingItems: Set<String> = ["share", "more"]
        private var observer: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard window != nil else { return }
            // SwiftUI fills the toolbar after the window appears and again as the window's panes change.
            observer = NotificationCenter.default.addObserver(
                forName: NSToolbar.willAddItemNotification, object: nil, queue: .main
            ) { [weak self] note in
                let toolbar = note.object as? NSToolbar
                MainActor.assumeIsolated {
                    guard let self, let toolbar, toolbar === self.window?.toolbar else { return }
                    DispatchQueue.main.async { Self.tidy(toolbar) }
                }
            }
            DispatchQueue.main.async { [weak self] in
                if let toolbar = self?.window?.toolbar { Self.tidy(toolbar) }
            }
        }

        private static func tidy(_ toolbar: NSToolbar) {
            let items = toolbar.items
            guard let search = items.firstIndex(where: { $0 is NSSearchToolbarItem }), search >= 2,
                  items[search - 1].itemIdentifier == .flexibleSpace,
                  trailingItems.contains(items[search - 2].itemIdentifier.rawValue)
            else { return }
            toolbar.removeItem(at: search - 1)
        }
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
