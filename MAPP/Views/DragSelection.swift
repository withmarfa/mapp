import SwiftUI

extension View {
    /// Lets the selected items be dragged together from a drag container (`dragContainer(for:)`).
    func dragsSelection(of browser: Browser) -> some View {
        modifier(DragSelection(browser: browser))
    }
}

/// Reads the selection in its own body, so a change of selection does not run the body of the list or the gallery
/// around it, which lists every item the place holds.
private struct DragSelection: ViewModifier {
    let browser: Browser

    func body(content: Content) -> some View {
        content.dragContainerSelection(Array(browser.selection))
    }
}
