import SwiftUI

/// The sidebar's controls in the window's title bar: the sidebar button, then Back and Forward in one capsule, against the
/// sidebar's trailing edge, with whatever room is left between them and the window's traffic lights. With the sidebar
/// closed the button stays and Back and Forward move to the leading column's toolbar (`WindowToolbar`, `ListToolbar`),
/// beside the traffic lights, which the top row measures and keeps clear of.
///
/// The system's own toolbar lays all of it out, so nothing here holds a position. The declarations that keep it so:
///
/// - The items are the sidebar column's and have automatic placement. A `.navigation` placement puts them after the
///   divider, over the next column.
/// - The sidebar button is declared here, in place of the system's (`toolbar(removing: .sidebarToggle)`), which always
///   stands last, after the column's own items.
/// - Back and Forward are one item. As two, a narrow sidebar sends Forward alone to the overflow menu.
/// - That item draws its own glass, apart from the toolbar's. Beside a fixed space instead, the pair joins the sidebar
///   button in one capsule once the sidebar has been hidden and shown: the system drops the space while the sidebar is
///   still narrow, and does not put it back.
/// - The sidebar is never narrower than these need (`ColumnWidth.sidebar`).
struct SidebarToolbar: ToolbarContent {
    let browser: Browser
    @Binding var isSidebarVisible: Bool
    @AppStorage(InterfaceKey.showsSidebarHistory) private var showsHistory = true

    var body: some ToolbarContent {
        ToolbarSpacer(.flexible)
        ToolbarItem { SidebarToggle(isSidebarVisible: $isSidebarVisible) }
        if isSidebarVisible, showsHistory {
            ToolbarItem { SidebarHistory(browser: browser) }
                .sharedBackgroundVisibility(.hidden)
        }
    }
}

private struct SidebarToggle: View {
    /// The window's own, rather than the `toggleSidebar(_:)` action, which only reaches the key window.
    @Binding var isSidebarVisible: Bool

    var body: some View {
        let action = isSidebarVisible ? Text("Hide Sidebar") : Text("Show Sidebar")
        // Short, as Icon and Text takes room from Back and Forward, which then need a wider sidebar. The toolbar takes a lone button's own
        // label for accessibility, so the button is in a container.
        HStack(spacing: 0) {
            Button("Sidebar", systemImage: "sidebar.left") { withAnimation { isSidebarVisible.toggle() } }
                .help(action)
                .accessibilityLabel(action)
                .accessibilityIdentifier("SidebarToggle")
        }
        .labelStyle(.iconOnly)
        .accessibilityElement(children: .contain)
    }
}
