import SwiftUI

extension View {
    /// Gives `opener` this window's way to open a main window, for an item link that comes while none is open. Any of
    /// the app's windows gives it, since only a view can open a window and the link may come while only Settings or an
    /// item's window is open.
    func opensItemLinks(_ opener: ItemLinkOpener) -> some View {
        modifier(ItemLinkWindows(opener: opener))
    }
}

private struct ItemLinkWindows: ViewModifier {
    let opener: ItemLinkOpener
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { opener.openMainWindow = { openWindow(id: MarfaMacApp.mainWindowID) } }
    }
}
