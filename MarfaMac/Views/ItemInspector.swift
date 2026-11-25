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
            if let id = selectedID, let item = library.headerItem(id) {
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

    /// Follows a link as Settings > Open Items says, as a link in the page does (`EditorController.follow`), so a window
    /// of its own opens it as that window does. With no page beside the panel, the item opens in another window. A
    /// deleted item opens in Recently Deleted where a main window has the panel, and as any link in a window of its own,
    /// whose page shows its deleted notice.
    private func open(_ id: ItemID) {
        if let browser, library.item(id)?.state == .trashed {
            browser.showSettings(.recentlyDeleted)
            return
        }
        guard library.item(id) != nil else { return }
        browser?.clearSearch()
        if let editor {
            editor.follow(id)
        } else if let browser, let item = library.item(id) {
            browser.follow(link: item, in: library, order: order)
        } else {
            openWindow(value: id)
        }
    }
}
