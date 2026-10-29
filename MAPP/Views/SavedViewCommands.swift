import SwiftUI

/// Saving what a window shows as a view on the Marfa server, and updating, renaming and deleting the view it shows.
/// Each needs the server, so each is offered only while the library can reach it (`ItemLibrary.canEditViews`).
enum SavedViews {
    /// Whether the window's place can be saved as a view: Recents, Recently Deleted, the indexes, a single favorite
    /// and a collection cannot.
    static func canSave(_ browser: Browser, in library: any ItemLibrary) -> Bool {
        library.isLoaded && library.canEditViews && !browser.showsSettings && !browser.showsSidebarIndex
            && ViewDraft.query(for: browser.item, catalogue: library.catalogue, views: library.views) != nil
    }

    /// The view the window shows, while the library holds it.
    static func shown(_ browser: Browser, in library: any ItemLibrary) -> LibraryView? {
        guard !browser.showsSettings, case .view(let id) = browser.item else { return nil }
        return library.views.first { $0.id == id }
    }

    /// What the window shows, as the table works it out. Only the table applies filters, so only its are taken.
    static func window(_ browser: Browser, in library: any ItemLibrary) -> ViewDraft.Window {
        let content = browser.tableContent(in: library)
        let options = browser.tableOptions[browser.item] ?? ItemTableOptions()
        let search = browser.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ViewDraft.Window(
            place: browser.item, columns: content.columns, sort: content.sort, grouping: content.grouping,
            filters: browser.viewMode == .table ? options.filters : [:], search: search.isEmpty ? nil : search)
    }

    /// What the window shows in the layout it shows it in, with that layout's own order and grouping, so a new
    /// view keeps what the person sees.
    static func window(_ browser: Browser, in library: any ItemLibrary, order: NoteOrder) -> ViewDraft.Window {
        var window = window(browser, in: library)
        switch browser.viewMode {
        case .table:
            window.layout = .table
        case .list, .gallery:
            window.layout = .list(order)
        case .board:
            let fields = browser.boardFieldChoices(in: library)
            let field = ItemBoardLayout.selectedField(browser.boardFields[browser.item], available: fields)
            window.layout = .board(key: field?.key, label: field?.label ?? "")
        case .timeline:
            let fields = browser.timelineFieldChoices(in: library)
            let key = ItemTimelineLayout.selectedField(browser.timelineFields[browser.item], fields: fields)
            window.layout = .timeline(key: key, label: fields.first { $0.key == key }?.displayLabel ?? "")
        }
        return window
    }

    /// Updates the view the window shows with the table's choices, asking first when it would leave some of the
    /// window out, or leave conditions of the view's filter the table cannot show as they are.
    static func update(_ browser: Browser, in library: any ItemLibrary) {
        guard let shown = shown(browser, in: library),
              let update = browser.viewUpdate(window(browser, in: library), in: library) else { return }
        guard update.unkept.isEmpty, update.change.query == nil || update.unchanged.isEmpty else {
            browser.viewEditing = .update(shown.id)
            return
        }
        Task { await save(update, of: shown.id, browser: browser, library: library) }
    }

    /// Saves the window's choices to the view at the version they were made on. A view changed elsewhere since is
    /// not overwritten: the window goes back to the view as it is.
    static func save(
        _ update: Browser.ViewUpdate,
        of id: ItemID, browser: Browser, library: any ItemLibrary
    ) async {
        // The window's filters may differ only in ones the view never held, so the window goes back to the view.
        guard !update.change.isEmpty else { return browser.viewUpdated(update.view) }
        switch await library.changeView(id, update.change, baseVersion: update.baseVersion) {
        case .success(let view): browser.viewUpdated(view)
        case .failure(let failure) where failure.kind == .conflict: browser.viewRefused(id, in: library)
        case .failure: break
        }
    }

    static func describe(_ unkept: ViewDraft.Unkept) -> String {
        switch unkept {
        case .search(let text): String(localized: "The search for “\(text)”")
        case .filter(let column): String(localized: "The filter on \(column)")
        case .mixedFilters: String(localized: "Filters that would join conditions with both “and” and “or”")
        case .tooManyFilters: String(localized: "Filters beyond the 10 conditions a view can hold")
        case .sort(let column): String(localized: "Sorting by \(column)")
        case .group(let column): String(localized: "Grouping by \(column)")
        case .dateSections: String(localized: "The list’s sections by date")
        }
    }
}

/// The saved-view commands as the command palette lists them.
struct SavedViewCommand {
    let title: String
    let systemImage: String
    let action: () -> Void

    static func commands(for browser: Browser, in library: any ItemLibrary) -> [SavedViewCommand] {
        guard library.canEditViews else { return [] }
        var commands: [SavedViewCommand] = []
        if SavedViews.canSave(browser, in: library) {
            commands.append(SavedViewCommand(title: String(localized: "New View…"), systemImage: "plus.rectangle.on.rectangle") {
                browser.viewEditing = .new
            })
        }
        if let view = SavedViews.shown(browser, in: library) {
            if browser.hasViewChanges {
                commands.append(SavedViewCommand(title: String(localized: "Update View"), systemImage: "arrow.trianglehead.2.clockwise") {
                    SavedViews.update(browser, in: library)
                })
            }
            commands.append(SavedViewCommand(title: String(localized: "Rename View…"), systemImage: "pencil") {
                browser.viewEditing = .rename(view.id)
            })
            commands.append(SavedViewCommand(title: String(localized: "Delete View…"), systemImage: "trash") {
                browser.viewEditing = .delete(view.id)
            })
        }
        return commands
    }
}

/// The saved-view commands in the View menu.
struct SavedViewMenu: View {
    let browser: Browser?
    let library: (any ItemLibrary)?

    var body: some View {
        let shown = browser.flatMap { browser in library.flatMap { SavedViews.shown(browser, in: $0) } }
        let canEdit = library?.canEditViews == true
        Button("New View…", systemImage: "plus.rectangle.on.rectangle") { browser?.viewEditing = .new }
            .disabled(!(browser.flatMap { browser in library.map { SavedViews.canSave(browser, in: $0) } } ?? false))
        Button("Update View", systemImage: "arrow.trianglehead.2.clockwise") {
            if let browser, let library { SavedViews.update(browser, in: library) }
        }
        .disabled(!canEdit || shown == nil || browser?.hasViewChanges != true)
        Button("Rename View…", systemImage: "pencil") {
            if let shown { browser?.viewEditing = .rename(shown.id) }
        }
        .disabled(!canEdit || shown == nil)
        Button("Delete View…", systemImage: "trash") {
            if let shown { browser?.viewEditing = .delete(shown.id) }
        }
        .disabled(!canEdit || shown == nil)
    }
}

/// The Views heading, with New View, which shows only while the pointer is over the heading, as the control of a
/// sidebar's section heading does.
struct ViewsHeading: View {
    let browser: Browser
    @CurrentLibrary private var library
    @State private var isHovering = false

    var body: some View {
        HStack {
            Text("Views")
            Spacer()
            Button("New View", systemImage: "plus") { browser.viewEditing = .new }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
                .disabled(!SavedViews.canSave(browser, in: library))
                .help(SavedViews.canSave(browser, in: library) ? Text("Save what this window shows as a view") : Text("This place can’t be saved as a view"))
                .accessibilityIdentifier("NewSavedView")
        }
        .padding(.trailing, 12)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }
}

/// A view row's own commands in the sidebar.
struct SavedViewRowMenu: View {
    let view: ItemID
    let browser: Browser
    @CurrentLibrary private var library

    var body: some View {
        Button("Rename View…") { browser.viewEditing = .rename(view) }
            .disabled(!library.canEditViews)
        Button("Delete View…") { browser.viewEditing = .delete(view) }
            .disabled(!library.canEditViews)
    }
}

extension View {
    /// Asks about each saved-view command the window gives, opens each view with its own order, grouping and the
    /// layout last used for it on this Mac, and keeps that layout as the person changes it.
    func savedViewDialogs(browser: Browser, order: NoteOrder) -> some View {
        modifier(SavedViewDialogs(browser: browser, order: order))
    }
}

private struct SavedViewDialogs: ViewModifier {
    @CurrentLibrary private var library
    let browser: Browser
    let order: NoteOrder
    /// The layout last used for each view on this Mac. It is MAPP's own and never written to Marfa.
    @AppStorage("savedViewLayouts") private var storedLayouts = Data()

    func body(content: Content) -> some View {
        content
            .sheet(item: sheet) { editing in
                SavedViewSheet(editing: editing, browser: browser, library: library, order: order) { id, mode in
                    remember(mode, for: id)
                }
            }
            .confirmationDialog(deleteTitle, isPresented: deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("The view is deleted for every app connected to your Marfa server. You can’t undo this action.")
            }
            .onChange(of: browser.item, initial: true) {
                openLayout()
                browser.followView(in: library)
            }
            .onChange(of: library.views) { browser.followView(in: library) }
            .onChange(of: browser.viewMode) {
                if case .view(let id) = browser.item { remember(browser.viewMode, for: id) }
            }
    }

    private var sheet: Binding<Browser.ViewEditing?> {
        Binding {
            switch browser.viewEditing {
            case .new, .rename, .update: browser.viewEditing
            case .delete, nil: nil
            }
        } set: { if $0 == nil { browser.viewEditing = nil } }
    }

    private var deletingID: ItemID? {
        if case .delete(let id) = browser.viewEditing { id } else { nil }
    }

    private var deleting: Binding<Bool> {
        Binding { deletingID != nil } set: { if !$0 { browser.viewEditing = nil } }
    }

    private var deleteTitle: String {
        let title = deletingID.flatMap { id in library.views.first { $0.id == id }?.title } ?? ""
        return String(localized: "Delete the view “\(title)”?")
    }

    private func delete() {
        guard let id = deletingID else { return }
        browser.viewEditing = nil
        Task {
            if await library.deleteView(id) { forget(id) }
        }
    }

    private var layouts: [String: ItemViewMode] {
        (try? JSONDecoder().decode([String: ItemViewMode].self, from: storedLayouts)) ?? [:]
    }

    private func remember(_ mode: ItemViewMode, for id: ItemID) {
        var layouts = layouts
        guard layouts[id.rawValue] != mode else { return }
        layouts[id.rawValue] = mode
        storedLayouts = (try? JSONEncoder().encode(layouts)) ?? storedLayouts
    }

    private func forget(_ id: ItemID) {
        var layouts = layouts
        guard layouts.removeValue(forKey: id.rawValue) != nil else { return }
        storedLayouts = (try? JSONEncoder().encode(layouts)) ?? storedLayouts
    }

    private func openLayout() {
        guard case .view(let id) = browser.item, let mode = layouts[id.rawValue],
              browser.availableViewModes(in: library).contains(mode) else { return }
        browser.viewMode = mode
    }
}

/// Asks for a new view's title, a view's new name, or whether to update a view with what it will not keep. A title
/// stays in the sheet until the server takes it (`ViewTitleForm`).
private struct SavedViewSheet: View {
    let editing: Browser.ViewEditing
    let browser: Browser
    let library: any ItemLibrary
    let order: NoteOrder
    /// Keeps the window's layout for a view it saved.
    let created: (ItemID, ItemViewMode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var update: Browser.ViewUpdate?
    @State private var unkept: [ViewDraft.Unkept] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading).font(.headline)
            switch editing {
            case .new:
                if let form = browser.viewTitleForm { ViewTitleField(form: form) }
            case .rename:
                if let form = browser.viewTitleForm { ViewTitleField(form: form) }
            case .update, .delete:
                Text("The view is updated for every app connected to your Marfa server.")
                    .foregroundStyle(.secondary)
            }
            if !unkept.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The view won’t keep:")
                    ForEach(unkept, id: \.self) { Text("• \(SavedViews.describe($0))") }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let update, update.change.query != nil, !update.unchanged.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The table can’t show these conditions of the view’s filter, so they stay as they are:")
                    ForEach(update.unchanged, id: \.self) { Text(verbatim: "• \($0)").monospaced() }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if browser.viewTitleForm?.isSaving == true { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button(action) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear(perform: read)
    }

    private var heading: String {
        switch editing {
        case .new: String(localized: "New View")
        case .rename: String(localized: "Rename View")
        case .update(let id), .delete(let id):
            String(localized: "Update “\(library.views.first { $0.id == id }?.title ?? "")”?")
        }
    }

    private var action: String {
        switch editing {
        case .new: String(localized: "Save View")
        case .rename: String(localized: "Rename")
        case .update, .delete: String(localized: "Update View")
        }
    }

    private var canSave: Bool {
        switch editing {
        case .new, .rename: browser.viewTitleForm?.canSubmit == true
        case .update, .delete: library.canEditViews
        }
    }

    private func read() {
        switch editing {
        case .new:
            let window = SavedViews.window(browser, in: library, order: order)
            guard let draft = ViewDraft.draft(window, catalogue: library.catalogue, views: library.views) else { return }
            unkept = draft.unkept
            browser.viewTitleForm = ViewTitleForm(
                new: draft, layout: browser.viewMode, title: library.name(of: browser.item), library: library)
        case .rename(let id):
            guard let view = library.views.first(where: { $0.id == id }) else { return }
            browser.viewTitleForm = ViewTitleForm(renaming: view, library: library)
        case .update:
            update = browser.viewUpdate(SavedViews.window(browser, in: library), in: library)
            unkept = update?.unkept ?? []
        case .delete:
            break
        }
    }

    private func close() {
        browser.viewTitleForm = nil
        browser.viewEditing = nil
        dismiss()
    }

    private func save() {
        switch editing {
        case .new, .rename:
            guard let form = browser.viewTitleForm else { return }
            Task { [browser, library, order, created] in
                guard case .done(let view) = await form.submit(), browser.viewTitleForm === form else { return }
                close()
                if case .new(_, let mode) = form.purpose, let view {
                    created(view.id, mode)
                    browser.show(.view(view.id), in: library, order: order)
                }
            }
        case .update(let id):
            dismiss()
            guard let update else { return }
            Task { [browser, library] in await SavedViews.save(update, of: id, browser: browser, library: library) }
        case .delete:
            break
        }
    }
}

/// The title a view sheet holds, which stays as typed until the server takes it.
private struct ViewTitleField: View {
    @Bindable var form: ViewTitleForm

    var body: some View {
        TextField("Title", text: $form.title)
            .disabled(form.isSaving)
    }
}
