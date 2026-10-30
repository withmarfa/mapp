import SwiftUI

extension View {
    /// Keeps the window's place and layout true to the library as it changes. The checks sit in a view of their own,
    /// behind the window, so a change that moves them re-runs only these few lines and never the window's body or
    /// the sidebar's.
    func watchesPlace(_ browser: Browser, order: NoteOrder) -> some View {
        background { PlaceWatch(browser: browser, order: order) }
    }
}

/// What a window does when the library changes under the place it shows: moves on from a place that is gone, goes
/// back to the list when its layout is no longer offered, and keeps a selection that follows the collection.
private struct PlaceWatch: View {
    @CurrentLibrary private var library
    let browser: Browser
    let order: NoteOrder

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: browser.placeFallback(in: library)) { browser.placeRemoved(in: library, order: order) }
            // The gallery or table disappears while an item is open; selection must still follow deletes and moves.
            .onChange(of: browser.collectionItemIDs(in: library, order: order)) { old, new in
                guard browser.usesCollection else { return }
                browser.keepSelection(from: old, to: new)
            }
            // A layout the place cannot show (Board with no choice fields) is not offered, and a window left on one
            // returns to the list. Changing `viewMode` only moves between layouts the workspace already handles.
            .onChange(of: browser.availableViewModes(in: library), initial: true) { browser.fallBackToListIfUnavailable(in: library) }
            .onChange(of: browser.viewMode) { browser.fallBackToListIfUnavailable(in: library) }
            // A place whose layouts match the last one's raises no change above, so a move to it is checked here.
            .onChange(of: browser.item) { browser.fallBackToListIfUnavailable(in: library) }
    }
}
