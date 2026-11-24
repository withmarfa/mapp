import SwiftUI

/// The sidebar's controls in the window's title bar: the sidebar button, then Back and Forward in one capsule, against the
/// sidebar's trailing edge, with whatever room is left between them and the window's traffic lights.
///
/// The system's own toolbar lays all of it out, so nothing here holds a position. The declarations that keep it so:
///
/// - The items are the sidebar column's and have automatic placement. A `.navigation` placement puts them after the
///   divider, over the next column.
/// - The sidebar button is declared here, in place of the system's (`toolbar(removing: .sidebarToggle)`), which always
///   stands last, after the column's own items. The system's is also not customizable content, and a plain `toolbar`
///   would turn customization off for the window.
/// - Back and Forward are one item. As two, a narrow sidebar sends Forward alone to the overflow menu.
/// - That item draws its own glass, apart from the toolbar's. Beside a fixed space instead, the pair joins the sidebar
///   button in one capsule once the sidebar has been hidden and shown: the system drops the space while the sidebar is
///   still narrow, and does not put it back.
/// - The sidebar is never narrower than these need (`ColumnWidth.sidebar`).
/// - All of it is always declared, and Back and Forward are hidden while they do not show: a layout the person has
///   customized never takes back an item that left it. Shown beside a hidden sidebar, they would go to an overflow menu at
///   the far end of the window.
struct SidebarToolbar: CustomizableToolbarContent {
    let browser: Browser
    @Binding var isSidebarVisible: Bool
    @AppStorage(InterfaceKey.showsSidebarHistory) private var showsHistory = true

    private var showsPair: Bool { isSidebarVisible && showsHistory }

    var body: some CustomizableToolbarContent {
        ToolbarSpacer(.flexible).customizationBehavior(.disabled)
        ToolbarItem(id: "sidebarToggle") { SidebarToggle(isSidebarVisible: $isSidebarVisible) }
            .customizationBehavior(.disabled)
        ToolbarItem(id: "sidebarHistory") {
            // A hidden item keeps its content's width, which would hold the sidebar button off the traffic lights.
            if showsPair { SidebarHistory(browser: browser) }
        }
            .sharedBackgroundVisibility(.hidden)
            .customizationBehavior(.disabled)
            .hidden(!showsPair)
    }
}

private struct SidebarToggle: View {
    /// The window's own, rather than the `toggleSidebar(_:)` action, which only reaches the key window.
    @Binding var isSidebarVisible: Bool

    var body: some View {
        Button { withAnimation { isSidebarVisible.toggle() } } label: {
            Label {
                if isSidebarVisible { Text("Hide Sidebar") } else { Text("Show Sidebar") }
            } icon: {
                Image(systemName: "sidebar.left")
            }
        }
        .help(isSidebarVisible ? Text("Hide Sidebar") : Text("Show Sidebar"))
        .accessibilityIdentifier("SidebarToggle")
    }
}

/// Back and Forward as the View menu has them. They are a container to accessibility, since the toolbar
/// otherwise gives Forward the label Back once the item has been put back.
private struct SidebarHistory: View {
    @CurrentLibrary private var library
    let browser: Browser

    /// The height of the toolbar's own glass.
    private static let height: CGFloat = 36

    var body: some View {
        HStack(spacing: 0) {
            Button("Back", systemImage: "chevron.backward") { browser.stepBack(in: library) }
                .disabled(!browser.canStepBack(in: library))
                .help("Back")
                .accessibilityIdentifier("SidebarBack")
            Button("Forward", systemImage: "chevron.forward") { browser.stepForward(in: library) }
                .disabled(!browser.canStepForward(in: library))
                .help("Forward")
                .accessibilityIdentifier("SidebarForward")
        }
        .labelStyle(.iconOnly)
        .frame(height: Self.height)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
    }
}
