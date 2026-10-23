import SwiftUI

struct Sidebar: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(\.undoManager) private var undoManager
    let browser: Browser
    let order: NoteOrder
    @State private var takenName: String?
    @SceneStorage("sidebarFavoritesExpanded") private var favoritesExpanded = true
    @SceneStorage("sidebarProjectsExpanded") private var projectsExpanded = true
    @SceneStorage("sidebarTypesExpanded") private var typesExpanded = true
    @SceneStorage("sidebarFoldersExpanded") private var foldersExpanded = true

    /// Picking an item shows it afresh. Clicking empty space would clear the selection, which the list
    /// cannot show, so that is ignored. While Settings shows, the row of Settings is the one selected, so
    /// choosing the place that was open before returns to it as it was.
    private var selection: Binding<SidebarItem?> {
        Binding {
            browser.showsSettings ? nil : browser.sidebarItem
        } set: { item in
            guard let item else { return }
            if item == browser.sidebarItem {
                browser.leaveSettings()
            } else {
                browser.show(item, in: library, order: order)
            }
        }
    }

    var body: some View {
        let plan = SidebarPlan(library, layout: libraries.sidebarLayout)
        List(selection: selection) {
            if !plan.shownTop.isEmpty {
                Section {
                    ForEach(plan.shownTop, id: \.key) { place in
                        switch place {
                        case .inbox: row(.inbox, systemImage: "tray", hiding: .inbox)
                        default: row(.allNotes, systemImage: "note.text", hiding: .all)
                        }
                    }
                }
            }

            if plan.isShown(.favorites), !favorites.isEmpty {
                Section(isExpanded: $favoritesExpanded) {
                    ForEach(favorites) { item in
                        sidebarLabel(item.title, systemImage: item.type == .project ? "square.stack" : "doc.text")
                            .tag(SidebarItem.favoriteItem(item.id))
                            .accessibilityIdentifier("SidebarFavoriteItem-\(item.id.rawValue)")
                    }
                } header: {
                    Text("Favorites")
                        .interfaceFont(.caption.weight(.semibold))
                        .accessibilityIdentifier("SidebarFavoritesSection")
                        .contextMenu { hideButton(.favorites) }
                }
            }

            if !plan.shownLibrary.isEmpty {
                Section {
                    ForEach(plan.shownLibrary, id: \.key) { place in
                        libraryRow(place, plan: plan)
                    }
                } header: {
                    Text("Library")
                        .interfaceFont(.caption.weight(.semibold))
                        .accessibilityIdentifier("SidebarLibrarySection")
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("Sidebar")
        .onDeleteCommand {
            if editsFolders { browser.folderToDelete = browser.selectedFolder }
        }
        .onChange(of: browser.renamingFolder) {
            if browser.renamingFolder != nil { foldersExpanded = true }
        }
        .onChange(of: favorites.map(\.id)) {
            browser.folderRemoved(in: library, order: order)
        }
        .confirmationDialog(
            "Delete the folder “\(folderToDelete?.name ?? "")”?",
            isPresented: Binding { folderToDelete != nil } set: { if !$0 { browser.folderToDelete = nil } },
            presenting: folderToDelete
        ) { folder in
            Button("Delete Folder", role: .destructive) {
                EditorController.flushAll(leaving: false) { [undoManager] kept in
                    guard kept else { return }
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

    @ViewBuilder private func libraryRow(_ place: SidebarPlace, plan: SidebarPlan) -> some View {
        switch place {
        case .projects:
            DisclosureGroup(isExpanded: $projectsExpanded) {
                ForEach(projects) { project in
                    row(.project(project.id), systemImage: "square.stack")
                }
            } label: {
                sidebarLabel(String(localized: "Projects"), systemImage: "square.stack")
                    .badge(library.count(in: .itemType(TypeID.project.rawValue)))
                    .contextMenu { hideButton(.projects) }
            }
            .tag(SidebarItem.itemType(TypeID.project.rawValue))
            .accessibilityIdentifier("SidebarProjects")
        case .types:
            DisclosureGroup(isExpanded: $typesExpanded) {
                ForEach(plan.shownTypes) { type in
                    row(.itemType(type.id.rawValue), systemImage: "doc.text", hiding: .type(type.id))
                }
            } label: {
                sidebarLabel(String(localized: "Types"), systemImage: "square.grid.2x2")
                    .contextMenu { hideButton(.types) }
            }
            .accessibilityIdentifier("SidebarTypes")
        case .folders:
            DisclosureGroup(isExpanded: $foldersExpanded) {
                ForEach(library.folders) { folder in
                    folderRow(folder)
                }
                .onMove(perform: editsFolders ? { source, destination in
                    let ids = source.map { library.folders[$0].id }
                    let target = destination < library.folders.count ? library.folders[destination].id : nil
                    library.moveFolders(ids, before: target, undoManager: undoManager)
                } : nil)
            } label: {
                sidebarLabel(String(localized: "Folders"), systemImage: "folder")
                    .contextMenu {
                        Button("New Folder") {
                            browser.newFolder(in: library, order: order, undoManager: undoManager)
                        }
                        .disabled(!library.isLoaded || !editsFolders)
                        Divider()
                        hideButton(.folders)
                    }
            }
            .accessibilityIdentifier("SidebarFolders")
        case .files:
            row(.files, systemImage: "doc", hiding: .files)
        case .inbox, .all, .favorites, .type:
            EmptyView()
        }
    }

    private var projects: [Item] {
        library.items(in: .itemType(TypeID.project.rawValue))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var favorites: [Item] {
        library.items(in: .favorites)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func hideButton(_ place: SidebarPlace) -> some View {
        Button("Hide from Sidebar") {
            libraries.updateSidebarLayout { $0.setHidden(place, true) }
        }
    }

    private func row(_ item: SidebarItem, systemImage: String, hiding place: SidebarPlace? = nil) -> some View {
        Label {
            Text(library.name(of: item))
                .interfaceFont(.body)
        } icon: {
            Image(systemName: systemImage)
                .interfaceFont(.body)
        }
            .badge(library.count(in: item))
            .tag(item)
            .dropDestination(for: NoteReference.self, isEnabled: Browser.canDrop(on: item, in: library)) { notes, _ in
                drop(notes, on: item)
            }
            .contextMenu {
                if let place { hideButton(place) }
            }
    }

    private func folderRow(_ folder: Folder) -> some View {
        Group {
            if browser.renamingFolder == folder.id {
                FolderNameField(folder: folder) { name in
                    rename(folder, to: name)
                }
            } else {
                sidebarLabel(folder.name, systemImage: "folder")
                    .badge(library.count(in: .folder(folder.id)))
            }
        }
        .interfaceFont(.body)
        .tag(SidebarItem.folder(folder.id))
        .dropDestination(for: NoteReference.self, isEnabled: Browser.canDrop(on: .folder(folder.id), in: library)) { notes, _ in
            drop(notes, on: .folder(folder.id))
        }
        .contextMenu {
            Button("Rename Folder") { browser.renamingFolder = folder.id }
                .disabled(!editsFolders)
            Button("Delete Folder", role: .destructive) {
                browser.folderToDelete = folder.id
            }
            .disabled(!editsFolders)
        }
    }

    private func sidebarLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title).interfaceFont(.body)
        } icon: {
            Image(systemName: systemImage).interfaceFont(.body)
        }
    }

    private var editsFolders: Bool { library.capabilities.contains(.folders) }

    private var folderToDelete: Folder? {
        browser.folderToDelete.flatMap { library.folder($0) }
    }

    private func drop(_ notes: [NoteReference], on item: SidebarItem) {
        guard Browser.canDrop(on: item, in: library) else { return }
        let ids = Set(notes.map(\.id))
        switch item {
        case .inbox: library.move(ids, to: nil, undoManager: undoManager)
        case .folder(let id): library.move(ids, to: id, undoManager: undoManager)
        case .allNotes, .favorites, .itemType, .project, .favoriteItem, .files, .recentlyDeleted: break
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
                .interfaceFont(.body)
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
    let _ = library.setFavorite([ItemPreviewFixtures.projectID, ItemPreviewFixtures.ticketID], true)
    Sidebar(browser: Browser(), order: NoteOrder())
        .environment(\.library, library)
        .environment(ItemPreviewFixtures.libraries(named: "MAPP.SidebarPreview"))
        .frame(width: 260, height: 740)
}

#Preview("Sidebar Without Favorites") {
    Sidebar(browser: Browser(), order: NoteOrder())
        .environment(\.library, ItemPreviewFixtures.library)
        .environment(ItemPreviewFixtures.libraries(named: "MAPP.SidebarPreview"))
        .frame(width: 260, height: 740)
}
#endif
