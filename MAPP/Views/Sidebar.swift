import SwiftUI

struct Sidebar: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    let browser: Browser
    let order: NoteOrder
    /// Kept after the dialog closes, so its title does not empty while it animates away.
    @State private var folderToDelete: Folder?
    @State private var takenName: String?

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

            Section("Folders") {
                ForEach(library.folders) { folder in
                    folderRow(folder)
                }
                .onMove { source, destination in
                    let ids = source.map { library.folders[$0].id }
                    let target = destination < library.folders.count ? library.folders[destination].id : nil
                    library.moveFolders(ids, before: target, undoManager: undoManager)
                }
            }

            Section {
                row(.recentlyDeleted, systemImage: "trash")
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("New Folder", systemImage: "plus.circle") {
                browser.newFolder(in: library, order: order, undoManager: undoManager)
            }
                .disabled(!library.isLoaded)
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
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

    private func row(_ item: SidebarItem, systemImage: String) -> some View {
        Label(library.name(of: item), systemImage: systemImage)
            .badge(library.count(in: item))
            .tag(item)
            .dropDestination(for: NoteReference.self, isEnabled: item != .allNotes) { notes, _ in
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
        case .recentlyDeleted: library.delete(ids, undoManager: undoManager)
        case .allNotes: break
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
