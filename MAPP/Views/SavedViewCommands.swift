import SwiftUI

/// The saved-view commands as the command palette lists them.
struct SavedViewCommand {
    let title: String
    let systemImage: String
    let action: () -> Void

    static func commands(for browser: Browser, in library: any ItemLibrary, order: NoteOrder) -> [SavedViewCommand] {
        var commands: [SavedViewCommand] = []
        let shown = SavedViews.shown(browser, in: library)
        if SavedViews.canEdit(browser, in: library) {
            commands.append(SavedViewCommand(title: String(localized: "Edit View"), systemImage: "slider.horizontal.3") {
                browser.openViewPanel(in: library)
            })
        }
        // Making, copying and deleting a view need the server. Saving and reverting what the window holds do not,
        // since a change of the layout or columns is the Mac's own.
        let reachesServer = library.reachesServer
        if reachesServer, SavedViews.canSave(browser, in: library) {
            commands.append(SavedViewCommand(title: String(localized: "New View"), systemImage: "plus.rectangle.on.rectangle") {
                browser.openNewViewPanel(in: library)
            })
            // A place that is not a view saves what it shows as one.
            if SavedViews.hasChoicesToKeep(browser, in: library) {
                commands.append(SavedViewCommand(title: String(localized: "Save as View…"), systemImage: "plus.rectangle.on.rectangle") {
                    browser.openNewViewPanel(in: library)
                })
            }
        }
        if let view = shown {
            if browser.hasViewChanges {
                commands.append(SavedViewCommand(title: String(localized: "Save View"), systemImage: "arrow.trianglehead.2.clockwise") {
                    SavedViews.save(browser, in: library, order: order)
                })
                commands.append(SavedViewCommand(title: String(localized: "Revert View"), systemImage: "arrow.uturn.backward") {
                    browser.revertView(in: library)
                })
            }
            if reachesServer {
                commands.append(SavedViewCommand(title: String(localized: "Duplicate View"), systemImage: "plus.square.on.square") {
                    Task { await browser.duplicateView(view.id, in: library, order: order) }
                })
                commands.append(SavedViewCommand(title: String(localized: "Delete View…"), systemImage: "trash") {
                    browser.deletingView = view.id
                })
            }
        }
        return commands
    }
}

/// The saved-view commands in the View menu.
struct SavedViewMenu: View {
    let browser: Browser?
    let library: (any ItemLibrary)?
    @StoredOrder private var order

    var body: some View {
        let shown = browser.flatMap { browser in library.flatMap { SavedViews.shown(browser, in: $0) } }
        let canEdit = library?.reachesServer == true
        let canSave = browser.flatMap { browser in library.map { SavedViews.canSave(browser, in: $0) } } ?? false
        Button("New View", systemImage: "plus.rectangle.on.rectangle") {
            if let browser, let library { browser.openNewViewPanel(in: library) }
        }
        .disabled(!canSave)
        Button("Edit View", systemImage: "slider.horizontal.3") {
            if let browser, let library { browser.openViewPanel(in: library) }
        }
        .disabled(!(browser.flatMap { browser in library.map { SavedViews.canEdit(browser, in: $0) } } ?? false))
        Button("Save as View…", systemImage: "plus.rectangle.on.rectangle") {
            if let browser, let library { browser.openNewViewPanel(in: library) }
        }
        .disabled(!canSave || shown != nil)
        Button("Duplicate View", systemImage: "plus.square.on.square") {
            if let browser, let library, let shown { Task { await browser.duplicateView(shown.id, in: library, order: order) } }
        }
        .disabled(!canEdit || shown == nil)
        Button("Save View", systemImage: "arrow.trianglehead.2.clockwise") {
            if let browser, let library { SavedViews.save(browser, in: library, order: order) }
        }
        .disabled(shown == nil || browser?.hasViewChanges != true)
        Button("Revert View", systemImage: "arrow.uturn.backward") {
            if let browser, let library { browser.revertView(in: library) }
        }
        .disabled(shown == nil || browser?.hasViewChanges != true)
        Button("Delete View…", systemImage: "trash") {
            if let shown { browser?.deletingView = shown.id }
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
            Button("New View", systemImage: "plus") { browser.openNewViewPanel(in: library) }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
                .disabled(!SavedViews.canSave(browser, in: library))
                .help(SavedViews.canSave(browser, in: library) ? Text("Make a view of what this window shows") : Text("This place can’t be saved as a view"))
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
    @StoredOrder private var order

    var body: some View {
        Button("Edit View") { browser.editView(view, in: library, order: order) }
        Button("Duplicate View") { Task { await browser.duplicateView(view, in: library, order: order) } }
            .disabled(!library.reachesServer)
        Divider()
        Button("Delete View…") { browser.deletingView = view }
            .disabled(!library.reachesServer)
    }
}

extension View {
    /// Asks before deleting a view, opens each view with its own order, grouping and the layout and columns this Mac
    /// keeps for it, and gives the panel that edits one the right sidebar.
    func savedViewDialogs(browser: Browser, details: DetailsPresentation) -> some View {
        modifier(SavedViewDialogs(browser: browser, details: details))
    }
}

private struct SavedViewDialogs: ViewModifier {
    @CurrentLibrary private var library
    let browser: Browser
    let details: DetailsPresentation

    func body(content: Content) -> some View {
        content
            .confirmationDialog(deleteTitle, isPresented: deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("The view is deleted for every app connected to your Marfa server. You can’t undo this action.")
            }
            .onChange(of: browser.item, initial: true) { browser.followView(in: library) }
            .onChange(of: library.views) {
                browser.followView(in: library)
                browser.reconcileViewPanel(in: library)
            }
            // The panel takes the right sidebar, and gives it back when it closes or the person closes the sidebar.
            .onChange(of: browser.showsViewPanel, initial: true) {
                if browser.showsViewPanel { details.beginViewPanel() } else { details.endViewPanel() }
            }
            .onChange(of: details.isPresented) { if !details.isPresented { browser.closeViewPanel(in: library) } }
    }

    private var deleting: Binding<Bool> {
        Binding { browser.deletingView != nil } set: { if !$0 { browser.deletingView = nil } }
    }

    private var deleteTitle: String {
        let title = browser.deletingView.flatMap { id in library.views.first { $0.id == id }?.title } ?? ""
        return String(localized: "Delete the view “\(title)”?")
    }

    private func delete() {
        guard let id = browser.deletingView else { return }
        Task { await browser.deleteView(id, in: library) }
    }
}
