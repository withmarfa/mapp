import SwiftUI

/// The saved-view commands as the command palette lists them.
struct SavedViewCommand {
    let title: String
    let systemImage: String
    let action: () -> Void

    static func commands(for browser: Browser, in library: any ItemLibrary, order: ItemOrder) -> [SavedViewCommand] {
        var commands: [SavedViewCommand] = []
        let shown = SavedViews.shown(browser, in: library)
        if SavedViews.canEdit(browser, in: library) {
            commands.append(SavedViewCommand(title: String(localized: "Edit View"), systemImage: "slider.horizontal.3") {
                browser.openViewPanel(in: library)
            })
        }
        // Making, copying and deleting a view need the server. Save View and Revert View are for a change the server did
        // not take, which the window keeps.
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
        if browser.offersResetView {
            commands.append(SavedViewCommand(title: String(localized: "Reset View"), systemImage: "arrow.uturn.backward") {
                browser.resetView(in: library)
            })
        }
        if let view = shown {
            if browser.hasViewChanges {
                commands.append(SavedViewCommand(title: String(localized: "Save View"), systemImage: "arrow.trianglehead.2.clockwise") {
                    browser.writeViewAgain()
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
    var shortcuts: ShortcutBindings?
    @StoredOrder private var order
    // Read by `offersResetView`, so a change of the default view draws the menu again.
    @AppStorage(PlaceDefaults.key) private var storedDefaults = Data()
    @AppStorage(PlaceDensities.key) private var storedDensities = Data()
    @AppStorage(ItemTableColumnLayouts.key) private var storedColumns = Data()

    var body: some View {
        let _ = (storedDefaults, storedDensities, storedColumns)
        let shown = browser.flatMap { browser in library.flatMap { SavedViews.shown(browser, in: $0) } }
        let canEdit = library?.reachesServer == true
        let canSave = browser.flatMap { browser in library.map { SavedViews.canSave(browser, in: $0) } } ?? false
        Button("New View", systemImage: "plus.rectangle.on.rectangle") {
            if let browser, let library { browser.openNewViewPanel(in: library) }
        }
        .shortcut(.newView, shortcuts)
        .disabled(!canSave)
        Button("Edit View", systemImage: "slider.horizontal.3") {
            if let browser, let library { browser.openViewPanel(in: library) }
        }
        .shortcut(.editView, shortcuts)
        .disabled(!(browser.flatMap { browser in library.map { SavedViews.canEdit(browser, in: $0) } } ?? false))
        Button("Save as View…", systemImage: "plus.rectangle.on.rectangle") {
            if let browser, let library { browser.openNewViewPanel(in: library) }
        }
        .shortcut(.saveAsView, shortcuts)
        .disabled(!canSave || shown != nil)
        Button("Reset View", systemImage: "arrow.uturn.backward") {
            if let browser, let library { browser.resetView(in: library) }
        }
        .shortcut(.resetView, shortcuts)
        .disabled(browser?.offersResetView != true)
        Button("Duplicate View", systemImage: "plus.square.on.square") {
            if let browser, let library, let shown { Task { await browser.duplicateView(shown.id, in: library, order: order) } }
        }
        .shortcut(.duplicateView, shortcuts)
        .disabled(!canEdit || shown == nil)
        Button("Save View", systemImage: "arrow.trianglehead.2.clockwise") {
            browser?.writeViewAgain()
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

/// The heading of the section that holds the saved views, with New View, which shows only while the pointer is over
/// the heading, as the control of a sidebar's section heading does.
struct ViewsHeading: View {
    let title: String
    let browser: Browser
    @CurrentLibrary private var library
    @State private var isHovering = false

    var body: some View {
        HStack {
            Text(title)
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
            .onChange(of: browser.shown, initial: true) {
                browser.placeChanged()
                browser.followView(in: library)
                browser.followPlaceDefault(in: library)
                browser.choicesChanged()
            }
            // A place's default view is read once the catalogue is, since a condition on a field is kept only while a type declares it.
            .onChange(of: library.isLoaded) { browser.followPlaceDefault(in: library) }
            // Entries of what no longer exists are forgotten once the copy reads whole, which can come after it is loaded.
            .onChange(of: library.syncReport.fill?.state) { browser.prunePlaceDefaults(in: library) }
            // Each change of the place's order, grouping or filters is one step of Undo and, in a saved view, a write.
            .onChange(of: browser.liveChoices, initial: true) { browser.choicesChanged() }
            .onChange(of: library.reachesServer, initial: true) { browser.reachabilityChanged(in: library) }
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
