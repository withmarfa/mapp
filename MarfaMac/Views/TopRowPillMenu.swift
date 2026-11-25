import SwiftUI

/// A pill's right-click menu: Edit View, then for a saved view Rename…, Duplicate View, Hide, Add to Sidebar and Delete
/// View…, which asks, since a view has no bin. The place's own view is the place itself, so it can't be hidden, renamed or
/// deleted. What needs the server is off while it can't be reached.
struct TopRowPillMenu: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    @Environment(Libraries.self) private var libraries
    let browser: Browser
    let choice: TopRowContent.Choice
    let place: Place
    let rename: () -> Void

    var body: some View {
        let view = choice.target.view
        Button("Edit View", systemImage: "slider.horizontal.3") { edit() }
        if case .saved(let id) = view {
            Button("Rename…", systemImage: "pencil", action: rename)
                .disabled(!library.reachesServer)
            Button("Duplicate View", systemImage: "plus.square.on.square") {
                Task { await browser.duplicateView(id, in: library, order: order) }
            }
            .disabled(!library.reachesServer)
        }
        if view != .own {
            Button(choice.isHidden ? "Show in Row" : "Hide", systemImage: choice.isHidden ? "eye" : "eye.slash") {
                browser.setHidden(view, !choice.isHidden, in: place, library: library, order: order)
            }
        }
        if case .saved(let id) = view {
            let row = SidebarPlace.view(id)
            let inSidebar = !libraries.sidebarLayout.isHidden(row)
            Button(inSidebar ? "Remove from Sidebar" : "Add to Sidebar", systemImage: inSidebar ? "minus.circle" : "sidebar.left") {
                libraries.updateSidebarLayout { $0.setHidden(row, inSidebar) }
            }
            Divider()
            Button("Delete View…", systemImage: "trash", role: .destructive) {
                browser.closeViewPanel(in: library)
                browser.deletingView = id
            }
            .disabled(!library.reachesServer)
        }
    }

    private func edit() {
        if case .saved(let id) = choice.target.view { return browser.editView(id, in: library, order: order) }
        if !browser.shown.isSame(choice.target) { browser.show(choice.target, in: library, order: order) }
        browser.openViewPanel(in: library)
    }
}
