import Marfa
import SwiftUI

struct ItemInspectorHost: View {
    @CurrentLibrary private var library
    @Environment(\.openWindow) private var openWindow
    @StoredOrder private var order
    let browser: Browser?
    let itemID: ItemID?
    let details: DetailsPresentation
    /// The page beside the panel, which lists the headings of the item on it and goes to one, for the Outline.
    /// Nil where no page is beside the panel, and the Outline then has no headings.
    var editor: EditorController?

    init(browser: Browser, details: DetailsPresentation, editor: EditorController? = nil) {
        self.browser = browser; itemID = nil; self.details = details; self.editor = editor
    }
    init(itemID: ItemID, details: DetailsPresentation = DetailsPresentation(), editor: EditorController? = nil) {
        self.itemID = itemID; browser = nil; self.details = details; self.editor = editor
    }

    private var selectedID: ItemID? { itemID ?? (browser?.selection.count == 1 ? browser?.selection.first : nil) }

    var body: some View {
        Group {
            if let browser, details.isEditingView, let panel = browser.viewPanel {
                ViewEditPanel(browser: browser, panel: panel)
                    .onExitCommand { browser.escapeViewPanel(in: library) }
            } else if let id = selectedID, let item = library.headerItem(id) {
                ItemPanelLoader(
                    item: item, relationships: library.relationships(for: id), mentions: library.bodyMentions(for: id), editor: editor,
                    details: details, onOpen: open
                )
                .id(id)
            } else if let browser, browser.selection.count > 1 {
                EmptyState(title: Text("^[\(browser.selection.count) item](inflect: true) selected"), detail: nil, actions: { EmptyView() })
            } else if selectedID != nil {
                // The library has not read the chosen item yet.
                if library.isLoaded && library.syncReport.phase == .current { Color.clear } else { InspectorReadingView() }
            } else {
                // A place with no items says so in the main area, and so does the list layout's page column.
                Color.clear
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ItemInspector")
    }

    /// Follows a link as Settings > Open Items says. In a window of its own, which has no list, the item opens in
    /// another window.
    private func open(_ id: ItemID) {
        guard let browser else {
            if library.item(id) != nil { openWindow(value: id) }
            return
        }
        browser.clearSearch()
        if library.item(id)?.state == .trashed {
            browser.showSettings(.recentlyDeleted)
            return
        }
        guard let item = library.item(id) else { return }
        browser.follow(link: item, in: library, order: order)
    }
}
