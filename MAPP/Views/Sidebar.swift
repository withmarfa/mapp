import SwiftUI

struct Sidebar: View {
    @Environment(NoteLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @Binding var selection: SidebarItem?
    @State private var renaming: Folder.ID?
    @State private var folderToDelete: Folder?

    var body: some View {
        List(selection: $selection) {
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
                    library.moveFolders(from: source, to: destination, undoManager: undoManager)
                }
            }

            Section {
                row(.recentlyDeleted, systemImage: "trash")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("New Folder", systemImage: "plus.circle", action: newFolder)
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .confirmationDialog(
            "Delete the folder “\(folderToDelete?.name ?? "")”?",
            isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
            presenting: folderToDelete
        ) { folder in
            Button("Delete Folder", role: .destructive) { deleteFolder(folder) }
        } message: { _ in
            Text("Its notes will be moved to Recently Deleted.")
        }
    }

    private func row(_ item: SidebarItem, systemImage: String) -> some View {
        Label(library.name(of: item), systemImage: systemImage)
            .badge(library.count(in: item))
            .tag(item)
            .dropDestination(for: NoteReference.self) { notes, _ in
                drop(notes, on: item)
            }
    }

    private func folderRow(_ folder: Folder) -> some View {
        Group {
            if renaming == folder.id {
                FolderNameField(folder: folder) { name in
                    library.rename(folder.id, to: name, undoManager: undoManager)
                    renaming = nil
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
            Button("Rename Folder") { renaming = folder.id }
            Button("Delete Folder", role: .destructive) { folderToDelete = folder }
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

    private func newFolder() {
        let folder = library.newFolder(undoManager: undoManager)
        selection = .folder(folder.id)
        renaming = folder.id
    }

    private func deleteFolder(_ folder: Folder) {
        if selection == .folder(folder.id) { selection = .allNotes }
        library.deleteFolder(folder.id, undoManager: undoManager)
    }
}

/// The folder's name as an editable field, focused when it appears. Return or leaving the field commits and
/// Escape cancels. The draft is seeded once from the folder's name.
private struct FolderNameField: View {
    let folder: Folder
    let commit: (String) -> Void
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(folder: Folder, commit: @escaping (String) -> Void) {
        self.folder = folder
        self.commit = commit
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
}
