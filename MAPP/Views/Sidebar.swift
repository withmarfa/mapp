import SwiftUI

struct Sidebar: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(\.undoManager) private var undoManager
    let browser: Browser
    let order: NoteOrder
    @State private var takenName: String?

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
                        case .inbox: row(.inbox, symbol: "tray", hiding: .inbox)
                        // Always the same number, so it says nothing.
                        case .recents: row(.recents, symbol: "clock", hiding: .recents, counted: false)
                        case .files: row(.files, symbol: "doc", hiding: .files)
                        default: row(.allNotes, symbol: "note.text", hiding: .all)
                        }
                    }
                }
            }

            ForEach(plan.shownLibrary, id: \.key) { section in
                switch section {
                case .collections: collectionsSection(plan)
                case .types: typesSection(plan)
                case .folders: foldersSection(plan)
                default: EmptyView()
                }
            }

            if plan.isShown(.favorites), !favorites.isEmpty {
                Section(isExpanded: expansion(.favorites)) {
                    ForEach(favorites) { item in
                        sidebarLabel(item.title, symbol: TypeSymbol.name(for: item.type, in: library.catalogue))
                            .tag(SidebarItem.favoriteItem(item.id))
                            .accessibilityIdentifier("SidebarFavoriteItem-\(item.id.rawValue)")
                    }
                } header: {
                    Text("Favorites")
                        .contextMenu { hideButton(.favorites) }
                        .accessibilityIdentifier("SidebarFavoritesSection")
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("Sidebar")
        .onDeleteCommand {
            if editsFolders { browser.folderToDelete = browser.selectedFolder }
        }
        .onChange(of: browser.renamingFolder) {
            if browser.renamingFolder != nil { libraries.updateSidebarLayout { $0.setCollapsed(.folders, false) } }
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

    /// What other items are filed under, two levels of it: a collection that has collections under it folds them
    /// open and shut, and opening any row lists everything filed under it.
    private func collectionsSection(_ plan: SidebarPlan) -> some View {
        Section(isExpanded: expansion(.collections)) {
            ForEach(plan.shownCollections) { node in
                if node.children.isEmpty {
                    collectionRow(node)
                } else {
                    DisclosureGroup(isExpanded: expansion(.collection(node.id))) {
                        ForEach(node.children) { collectionRow($0) }
                    } label: {
                        collectionRow(node)
                    }
                }
            }
        } header: {
            Text("Collections")
                .contextMenu { hideButton(.collections) }
                .accessibilityIdentifier("SidebarCollections")
        }
    }

    private func collectionRow(_ node: CollectionNode) -> some View {
        row(.collection(node.id), symbol: node.symbol, title: node.title, hiding: .collection(node.id))
            .accessibilityIdentifier("SidebarCollection-\(node.id.rawValue)")
    }

    private func typesSection(_ plan: SidebarPlan) -> some View {
        Section(isExpanded: expansion(.types)) {
            ForEach(plan.shownTypes) { typeRow($0) }
        } header: {
            Text("Types")
                .contextMenu { hideButton(.types) }
                .accessibilityIdentifier("SidebarTypes")
        }
    }

    /// A type opens its own items; a type with subtypes also folds them open, and a group only folds. Erased, since
    /// a row holds rows of its own kind.
    private func typeRow(_ node: TypeNode) -> AnyView {
        guard !node.children.isEmpty else { return AnyView(typeLabel(node)) }
        return AnyView(DisclosureGroup(isExpanded: expansion(.type(node.id))) {
            ForEach(node.children) { typeRow($0) }
        } label: {
            typeLabel(node)
        })
    }

    @ViewBuilder private func typeLabel(_ node: TypeNode) -> some View {
        if node.opens, let type = node.type {
            row(.itemType(type.rawValue), symbol: node.symbol, title: node.label, hiding: .type(node.id))
                .accessibilityIdentifier("SidebarType-\(node.id)")
        } else {
            sidebarLabel(node.label, symbol: node.symbol)
                .selectionDisabled()
                .contextMenu { hideButton(.type(node.id)) }
                .accessibilityIdentifier("SidebarTypeGroup-\(node.id)")
        }
    }

    private func foldersSection(_ plan: SidebarPlan) -> some View {
        Section(isExpanded: expansion(.folders)) {
            ForEach(library.folders) { folder in
                folderRow(folder)
            }
            .onMove(perform: editsFolders ? { source, destination in
                let ids = source.map { library.folders[$0].id }
                let target = destination < library.folders.count ? library.folders[destination].id : nil
                library.moveFolders(ids, before: target, undoManager: undoManager)
            } : nil)
        } header: {
            Text("Folders")
                .contextMenu {
                    Button("New Folder") {
                        browser.newFolder(in: library, order: order, undoManager: undoManager)
                    }
                    .disabled(!library.isLoaded || !editsFolders)
                    Divider()
                    hideButton(.folders)
                }
                .accessibilityIdentifier("SidebarFolders")
        }
    }

    /// A section's or a row's disclosure, kept in the library's sidebar layout so it is remembered for each library.
    /// Everything starts open.
    private func expansion(_ section: SidebarPlace) -> Binding<Bool> {
        Binding {
            !libraries.sidebarLayout.isCollapsed(section)
        } set: { isExpanded in
            libraries.updateSidebarLayout { $0.setCollapsed(section, !isExpanded) }
        }
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

    private func row(
        _ item: SidebarItem, symbol: String, title: String? = nil, hiding place: SidebarPlace? = nil, counted: Bool = true
    ) -> some View {
        sidebarLabel(title ?? library.name(of: item), symbol: symbol)
            .badge(counted ? count(in: item) : nil)
            .tag(item)
            .dropDestination(for: NoteReference.self, isEnabled: Browser.canDrop(on: item, in: library)) { notes, _ in
                drop(notes, on: item)
            }
            .contextMenu {
                if let place { hideButton(place) }
            }
    }

    /// The count at the row's trailing edge, in secondary text with digits that line up; none where it is zero.
    private func count(in item: SidebarItem) -> Text? {
        let count = library.count(in: item)
        return count > 0 ? Text(count, format: .number).monospacedDigit() : nil
    }

    private func folderRow(_ folder: Folder) -> some View {
        Group {
            if browser.renamingFolder == folder.id {
                FolderNameField(folder: folder) { name in
                    rename(folder, to: name)
                }
            } else {
                sidebarLabel(folder.name, symbol: "folder")
                    .badge(count(in: .folder(folder.id)))
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

    private func sidebarLabel(_ title: String, symbol: String) -> some View {
        Label {
            Text(title).interfaceFont(.body)
        } icon: {
            Image(systemName: symbol).interfaceFont(.body)
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
        case .recents, .allNotes, .favorites, .itemType, .collection, .favoriteItem, .files, .recentlyDeleted: break
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
