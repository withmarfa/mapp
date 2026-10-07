import SwiftUI

/// The list workspace keeps its existing customizable toolbar and item identities.
struct NoteToolbar: CustomizableToolbarContent {
    @CurrentLibrary private var library
    let browser: Browser?
    let items: [Item]
    let editor: EditorController
    let details: DetailsPresentation

    private var tools: ItemToolbarActions {
        ItemToolbarActions(library: library, browser: browser, items: items, editor: editor, details: details)
    }

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "scrolledTitle") {
            Text(tools.notes.first?.title ?? "")
                .interfaceFont(.headline).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 220, alignment: .leading)
                .accessibilityIdentifier("ScrolledItemTitle")
        }
        .sharedBackgroundVisibility(.hidden)
        .customizationBehavior(.disabled)
        .hidden(!editor.isHeaderScrolledAway || tools.notes.count != 1 || browser?.isCreatingItem == true || browser?.showsGallery == true || tools.showsTypes)
        ToolbarSpacer(.flexible)
        ToolbarItem(id: "newNote") { NewNoteButton(browser: browser) }
            .customizationBehavior(.disabled)
            .hidden(browser == nil)
        ToolbarItem(id: "format") { FormatMenu(editor: editor, note: tools.editableNote) }
            .hidden(tools.showsTypes || browser?.showsGallery == true)
        ToolbarItem(id: "details") { tools.detailsButton }
            .hidden(tools.showsTypes)
        ToolbarItem(id: "more") { tools.moreMenu }
            .hidden(tools.showsTypes)
    }
}

/// Gallery shares the item actions without a second customizable toolbar configuration.
struct GalleryToolbar: ToolbarContent {
    @CurrentLibrary private var library
    let browser: Browser
    let items: [Item]
    let editor: EditorController
    let details: DetailsPresentation

    var body: some ToolbarContent {
        let tools = ItemToolbarActions(library: library, browser: browser, items: items, editor: editor, details: details)
        if !browser.showsGallery, !browser.isCreatingItem, editor.isHeaderScrolledAway, tools.notes.count == 1 {
            ToolbarItem(placement: .navigation) {
                Text(tools.notes.first?.title ?? "")
                    .interfaceFont(.headline).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 220, alignment: .leading)
                    .accessibilityIdentifier("ScrolledItemTitle")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            NewNoteButton(browser: browser)
            if !browser.showsGallery { FormatMenu(editor: editor, note: tools.editableNote) }
            tools.detailsButton
            tools.moreMenu
        }
    }
}

private struct ItemToolbarActions {
    let library: any ItemLibrary
    let browser: Browser?
    let items: [Item]
    let editor: EditorController
    let details: DetailsPresentation

    var notes: [Item] { items.filter { !$0.isFile } }
    var showsTypes: Bool { browser?.showsTypes == true }

    var visibleNote: Item? {
        guard browser?.isCreatingItem != true, browser?.showsGallery != true,
              (browser?.selection.count ?? notes.count) == 1, notes.count == 1,
              let note = notes.first, editor.hasNote, editor.noteID == note.id else { return nil }
        return note
    }

    /// Formatting acts only on the writable note currently visible in the editor.
    var editableNote: Item? { visibleNote.flatMap { $0.isWritable ? $0 : nil } }

    private var selectedFileURL: URL? {
        guard browser?.isCreatingItem != true, browser?.selection.count == 1,
              let id = browser?.selection.first else { return nil }
        return browser?.fileURL(of: id, in: library)
    }

    var detailsButton: some View {
        Button("Details", systemImage: "info.circle") { details.isPresented.toggle() }
            .help(details.isPresented ? "Hide Details" : "Show Details")
            .disabled((browser?.selection.count ?? notes.count) != 1 || browser?.isCreatingItem == true)
            .accessibilityIdentifier("DetailsToggle")
    }

    var moreMenu: some View {
        MoreMenu(notes: browser?.isCreatingItem != true && (browser?.selection.count ?? notes.count) == notes.count ? notes : [],
                 fileURL: selectedFileURL, browser: browser, editor: editor, editableNote: editableNote)
    }
}

private struct NewNoteButton: View {
    @CurrentLibrary private var library
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
    let note: Item?

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
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let notes: [Item]
    let fileURL: URL?
    let browser: Browser?
    let editor: EditorController
    let editableNote: Item?

    var body: some View {
        Menu("More", systemImage: "ellipsis") {
            if let browser {
                ItemViewOptions(browser: browser)
                Divider()
            }
            let note = notes.count == 1 ? notes.first : nil
            NoteShareLink(title: note?.title ?? "", text: note.flatMap { library.body(of: $0.id)?.text }, fileURL: fileURL)
            Button("Add Attachment…", systemImage: "paperclip") { editor.isChoosingImages = true }
                .disabled(editableNote == nil)
            Divider()
            if let browser {
                Button("Rename…", systemImage: "pencil") { browser.renamingNote = notes.first?.id }
                    .disabled(notes.count != 1 || !library.canRenameFile(of: notes.first))
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

/// Shares a note's markdown as text, the form every destination can take, or a file as itself.
struct NoteShareLink: View {
    var title = ""
    /// Nil when there is no one note to share.
    let text: String?
    var fileURL: URL? = nil

    var body: some View {
        if let fileURL {
            ShareLink(item: fileURL)
        } else if let text {
            ShareLink(item: text, subject: Text(title), preview: SharePreview(title))
        } else {
            ShareLink(item: "")
                .disabled(true)
        }
    }
}
