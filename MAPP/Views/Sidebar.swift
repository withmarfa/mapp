import SwiftUI

struct Sidebar: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    let browser: Browser
    let order: NoteOrder
    /// Kept after the dialog closes, so its title does not empty while it animates away.
    @State private var folderToDelete: Folder?
    @State private var takenName: String?
    @Environment(\.sidebarRowSize) private var rowSize

    /// Picking an item shows it afresh. Clicking empty space would clear the selection, which the list
    /// cannot show, so that is ignored.
    private var selection: Binding<SidebarItem?> {
        Binding {
            browser.sidebarItem
        } set: { item in
            guard let item, item != browser.sidebarItem else { return }
            browser.show(item, in: library, order: order)
        }
    }

    var body: some View {
        List(selection: selection) {
            Section {
                row(.inbox, systemImage: "tray")
                row(.allNotes, systemImage: "note.text")
                row(.pinned, systemImage: "pin")
            }

            Section {
                ForEach(library.folders) { folder in
                    folderRow(folder)
                }
                .onMove { source, destination in
                    let ids = source.map { library.folders[$0].id }
                    let target = destination < library.folders.count ? library.folders[destination].id : nil
                    library.moveFolders(ids, before: target, undoManager: undoManager)
                }
            } header: {
                FoldersHeader {
                    browser.newFolder(in: library, order: order, undoManager: undoManager)
                }
                .disabled(!library.isLoaded)
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("Sidebar")
        .onDeleteCommand {
            browser.folderToDelete = browser.selectedFolder
        }
        .onChange(of: browser.folderToDelete) {
            if let id = browser.folderToDelete { folderToDelete = library.folder(id) }
        }
        // A bar rather than an inset, so folders scrolling under the places fade as content does under a toolbar.
        .safeAreaBar(edge: .bottom, spacing: 0) {
            places
                .padding(.bottom, 8)
        }
        .confirmationDialog(
            "Delete the folder “\(folderToDelete?.name ?? "")”?",
            isPresented: Binding { browser.folderToDelete != nil } set: { if !$0 { browser.folderToDelete = nil } },
            presenting: folderToDelete
        ) { folder in
            Button("Delete Folder", role: .destructive) {
                EditorController.flushAll(leaving: false) { [undoManager] in
                    library.deleteFolder(folder.id, undoManager: undoManager)
                }
            }
        } message: { _ in
            Text("Its notes will be moved to Recently Deleted.")
        }
        .alert("Name Taken", isPresented: Binding { takenName != nil } set: { if !$0 { takenName = nil } }) {
        } message: {
            Text("A folder named “\(takenName ?? "")” already exists. Please choose a different name.")
        }
    }

    /// Marfa Types and Recently Deleted, kept at the foot of the sidebar however many folders there are. They
    /// are a list of their own, selected as the sidebar's other places are, sized to its two rows.
    private var places: some View {
        List(selection: selection) {
            row(.marfaTypes, systemImage: "cube")
            row(.recentlyDeleted, systemImage: "trash")
        }
        .listStyle(.sidebar)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .frame(height: 2 * rowHeight)
        .accessibilityIdentifier("SidebarPlaces")
        .accessibilityLabel("Places")
    }

    /// A sidebar row's height at the size chosen in System Settings, which the list of the places at its foot is
    /// given, since a list takes the height it is offered rather than its rows'.
    private var rowHeight: CGFloat {
        switch rowSize {
        case .small: 26
        case .large: 40
        default: 32
        }
    }

    private func row(_ item: SidebarItem, systemImage: String) -> some View {
        Label(library.name(of: item), systemImage: systemImage)
            .badge(library.count(in: item))
            .tag(item)
            .dropDestination(for: NoteReference.self, isEnabled: item != .allNotes && item != .marfaTypes) { notes, _ in
                drop(notes, on: item)
            }
    }

    private func folderRow(_ folder: Folder) -> some View {
        Group {
            if browser.renamingFolder == folder.id {
                FolderNameField(folder: folder) { name in
                    rename(folder, to: name)
                }
            } else {
                Label(folder.name, systemImage: "folder")
                    .badge(library.count(in: .folder(folder.id)))
            }
        }
        .tag(SidebarItem.folder(folder.id))
        .dropDestination(for: NoteReference.self) { notes, _ in
            drop(notes, on: .folder(folder.id))
        }
        .contextMenu {
            Button("Rename Folder") { browser.renamingFolder = folder.id }
            Button("Delete Folder", role: .destructive) {
                browser.folderToDelete = folder.id
            }
        }
    }

    private func drop(_ notes: [NoteReference], on item: SidebarItem) {
        let ids = Set(notes.map(\.id))
        switch item {
        case .inbox: library.move(ids, to: nil, undoManager: undoManager)
        case .folder(let id): library.move(ids, to: id, undoManager: undoManager)
        case .pinned: library.setPinned(ids, true, undoManager: undoManager)
        case .recentlyDeleted: library.deleteAfterSaving(ids, undoManager: undoManager)
        case .allNotes, .marfaTypes: break
        }
    }

    /// A name another folder has is refused with an alert, as the Finder does, and the old name stays.
    private func rename(_ folder: Folder, to name: String) {
        browser.renamingFolder = nil
        if library.isFolderNameTaken(name, except: folder.id) {
            takenName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            library.rename(folder.id, to: name, undoManager: undoManager)
        }
    }
}

/// The Folders heading, with a button for a new folder that shows while the pointer is over it, as Mail's
/// headings show theirs, in line with the rows' counts. The list reads a heading as one line, so the button is
/// left to the pointer; New Folder in the File menu, on ⇧⌘N, is there for everything else.
private struct FoldersHeader: View {
    let newFolder: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack {
            Text("Folders")
            Spacer()
            Button("New Folder", systemImage: "plus", action: newFolder)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("New Folder")
                .opacity(isHovering ? 1 : 0)
                .accessibilityHidden(true)
        }
        // A heading runs to the list's edge, past where the rows end their counts.
        .padding(.trailing, 14)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }
}

/// The folder's name as an editable field, focused when it appears. Return or leaving the field commits and
/// Escape cancels. The draft is seeded once from the folder's name. Return also takes the focus away, so the
/// field commits only the first time.
private struct FolderNameField: View {
    let folder: Folder
    let onCommit: (String) -> Void
    @State private var name: String
    @State private var isCommitted = false
    @FocusState private var isFocused: Bool

    init(folder: Folder, onCommit: @escaping (String) -> Void) {
        self.folder = folder
        self.onCommit = onCommit
        _name = State(initialValue: folder.name)
    }

    var body: some View {
        Label {
            TextField("Folder Name", text: $name)
                .focused($isFocused)
                .onSubmit { commit(name) }
                .onExitCommand { commit(folder.name) }
                .onChange(of: isFocused) { if !isFocused { commit(name) } }
        } icon: {
            Image(systemName: "folder")
        }
        .onAppear { isFocused = true }
    }

    private func commit(_ name: String) {
        guard !isCommitted else { return }
        isCommitted = true
        onCommit(name)
    }
}
