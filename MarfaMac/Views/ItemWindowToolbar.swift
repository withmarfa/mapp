import SwiftUI

/// The toolbar of an item's window: Back and Forward once a link has been followed in it, the title once the page's
/// head has scrolled away, then Keep on an item in the Feed, Favorite, Share and More, and the panel's button. It holds
/// the controls of the modal and of the main window's page, so an item reads the same wherever it opens.
struct ItemWindowToolbar: ToolbarContent {
    @CurrentLibrary private var library
    @AppStorage(InterfaceKey.showsScrolledTitle) private var showsScrolledTitle = true
    let tools: ItemToolbarActions
    let history: ItemWindowHistory
    /// Goes Back or Forward, which the window does once its page is handed over (`ItemWindow.go`).
    let go: (ItemWindowHistory.Step) -> Void

    var body: some ToolbarContent {
        let isAvailable: (ItemID) -> Bool = { library.item($0) != nil }
        let id = tools.ids.count == 1 ? tools.ids.first : nil
        if history.canGoBack(isAvailable: isAvailable) {
            ToolbarItem(placement: .navigation) {
                Button("Back", systemImage: "chevron.backward") { go(.back) }
                    .help("Back")
                    .accessibilityIdentifier("WindowBack")
            }
        }
        if history.canGoForward(isAvailable: isAvailable) {
            ToolbarItem(placement: .navigation) {
                Button("Forward", systemImage: "chevron.forward") { go(.forward) }
                    .help("Forward")
                    .accessibilityIdentifier("WindowForward")
            }
        }
        // A window of its own has no top row, so the page's title is an item of its toolbar once its head has scrolled.
        if showsScrolledTitle || tools.isFocused, let head = tools.scrolledPageTitle {
            ToolbarItem {
                ScrolledItemTitle(title: head.title, icon: head.icon, showsIcon: true, subtitle: head.subtitle)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        ToolbarSpacer(.flexible)
        if let id, PageKeepButton.applies(to: id, in: library) {
            ToolbarItem { tools.withUndo { PageKeepButton(id: id, undoManager: $0).labelStyle(.titleAndIcon) } }
        }
        ToolbarItemGroup {
            tools.withUndo { FavoriteButton(ids: tools.ids, undoManager: $0) }
            tools.shareLink
            tools.moreMenu.disabled(tools.items.isEmpty)
        }
        ToolbarSpacer(.fixed)
        ToolbarItem { tools.detailsButton }
    }
}
