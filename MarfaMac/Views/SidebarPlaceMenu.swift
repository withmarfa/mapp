import SwiftUI

/// A place's context menu: a view's own commands, the section it can move to, Remove from Sidebar and Customize
/// Sidebar.
struct SidebarPlaceMenu: View {
    @Environment(Libraries.self) private var libraries
    @CurrentLibrary private var library
    let data: SidebarPlaceRowData
    let groups: [SidebarGroupChoice]
    let customizing: Bool
    let browser: Browser
    let order: ItemOrder

    var body: some View {
        let place = data.place
        if case .view(let id) = place {
            Button("Edit View") { browser.editView(id, in: library, order: order) }
            Button("Duplicate View") { Task { await browser.duplicateView(id, in: library, order: order) } }
                .disabled(!library.reachesServer)
            Divider()
            Button("Delete View…") { browser.deletingView = id }
                .disabled(!library.reachesServer)
            Divider()
        }
        let targets = groups.filter { SidebarGroup(id: $0.id, kind: $0.kind, tab: "").holds(place) }
        if !targets.isEmpty {
            Menu("Move to Section") {
                ForEach(targets) { group in
                    Button(group.name) { libraries.updateSidebarLayout { $0.put(place, in: group.id) } }
                }
            }
            Divider()
        }
        Button("Remove from Sidebar") { libraries.updateSidebarLayout { $0.take(place) } }
        if !customizing {
            Divider()
            SidebarCustomizeButton(browser: browser)
        }
    }
}
