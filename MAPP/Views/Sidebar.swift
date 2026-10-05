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
    @SceneStorage("sidebarPinnedExpanded") private var pinnedExpanded = true
    @SceneStorage("sidebarProjectsExpanded") private var projectsExpanded = true
    @SceneStorage("sidebarItemsExpanded") private var itemsExpanded = false
    @SceneStorage("sidebarFoldersExpanded") private var foldersExpanded = true

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
            }

            if !pinned.isEmpty {
                Section(isExpanded: $pinnedExpanded) {
                    ForEach(pinned) { item in
                        Label(item.title, systemImage: item.type?.id == "aic.project" ? "square.stack" : "doc.text")
                            .tag(SidebarItem.pinnedItem(item.id))
                            .accessibilityIdentifier("SidebarPinnedItem-\(item.id.uuidString)")
                    }
                } header: {
                    Text("Pinned")
                        .accessibilityIdentifier("SidebarPinnedSection")
                }
            }

            Section {
                DisclosureGroup(isExpanded: $projectsExpanded) {
                    ForEach(projects) { project in
                        row(.project(project.id), systemImage: "square.stack")
                    }
                } label: {
                    Label("Projects", systemImage: "square.stack")
                        .badge(library.count(in: .itemType("aic.project")))
                }
                .tag(SidebarItem.itemType("aic.project"))
                .accessibilityIdentifier("SidebarProjects")

                DisclosureGroup(isExpanded: $itemsExpanded) {
                    ForEach(itemTypes) { type in
                        row(.itemType(type.id), systemImage: "doc.text")
                    }
                    row(.files, systemImage: "doc")
                } label: {
                    Label("Items", systemImage: "doc.text")
                }
                .accessibilityIdentifier("SidebarItems")

                DisclosureGroup(isExpanded: $foldersExpanded) {
                    ForEach(library.folders) { folder in
                        folderRow(folder)
                    }
                    .onMove { source, destination in
                        let ids = source.map { library.folders[$0].id }
                        let target = destination < library.folders.count ? library.folders[destination].id : nil
                        library.moveFolders(ids, before: target, undoManager: undoManager)
                    }
                } label: {
                    Label("Folders", systemImage: "folder")
                        .contextMenu {
                            Button("New Folder") {
                                browser.newFolder(in: library, order: order, undoManager: undoManager)
                            }
                            .disabled(!library.isLoaded)
                        }
                }
                .accessibilityIdentifier("SidebarFolders")
            } header: {
                Text("Library")
                    .accessibilityIdentifier("SidebarLibrarySection")
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
        .onChange(of: browser.renamingFolder) {
            if browser.renamingFolder != nil { foldersExpanded = true }
        }
        .onChange(of: pinned.map(\.id)) {
            browser.folderRemoved(in: library, order: order)
        }
        .scrollEdgeEffectHidden(for: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
            row(.marfaTypes, systemImage: "cube", secondaryIcon: true)
            row(.recentlyDeleted, systemImage: "trash", secondaryIcon: true)
        }
        .listStyle(.sidebar)
        .scrollDisabled(true)
        .scrollEdgeEffectHidden(for: .top)
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

    private var projects: [AppItem] {
        library.items.filter { $0.type?.id == "aic.project" }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var pinned: [AppItem] {
        library.notes(in: .pinned)
            .compactMap { library.item($0.id) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var itemTypes: [ItemTypeDefinition] {
        WorkbenchSchema.types.filter { $0.id != "aic.project" }
    }

    private func row(_ item: SidebarItem, systemImage: String, secondaryIcon: Bool = false) -> some View {
        Label {
            Text(library.name(of: item))
        } icon: {
            if secondaryIcon {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: systemImage)
            }
        }
            .badge(library.count(in: item))
            .tag(item)
            .dropDestination(for: NoteReference.self, isEnabled: canDrop(on: item)) { notes, _ in
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

    private func canDrop(on item: SidebarItem) -> Bool {
        switch item {
        case .inbox, .folder, .recentlyDeleted: true
        default: false
        }
    }

    private func drop(_ notes: [NoteReference], on item: SidebarItem) {
        let ids = Set(notes.map(\.id))
        switch item {
        case .inbox: library.move(ids, to: nil, undoManager: undoManager)
        case .folder(let id): library.move(ids, to: id, undoManager: undoManager)
        case .recentlyDeleted: library.deleteAfterSaving(ids, undoManager: undoManager)
        case .allNotes, .pinned, .marfaTypes, .itemType, .project, .pinnedItem, .files: break
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
/// Escape cancels. List can retain the field's state between edits, so each appearance starts a fresh draft
/// and commit guard. Return also takes the focus away, so each edit commits only once.
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
        .onAppear {
            name = folder.name
            isCommitted = false
            isFocused = true
        }
    }

    private func commit(_ name: String) {
        guard !isCommitted else { return }
        isCommitted = true
        onCommit(name)
    }
}

#if DEBUG
#Preview("Grouped Sidebar") {
    let source = ItemPreviewFixtures.library
    let library = NoteLibrary(notes: source.notes, folders: [Folder(name: "Projects"), Folder(name: "Notes")], now: { ItemPreviewFixtures.date })
    let _ = library.setPinned([ItemPreviewFixtures.projectID, ItemPreviewFixtures.ticketID], true)
    Sidebar(browser: Browser(), order: NoteOrder())
        .environment(library)
        .frame(width: 260, height: 740)
}

#Preview("Sidebar Without Pins") {
    Sidebar(browser: Browser(), order: NoteOrder())
        .environment(ItemPreviewFixtures.library)
        .frame(width: 260, height: 740)
}
#endif
