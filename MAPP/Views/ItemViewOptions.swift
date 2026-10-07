import SwiftUI

struct ItemViewOptions: View {
    @Bindable var browser: Browser

    var body: some View {
        Picker("View", selection: $browser.viewMode) {
            Label("List View", systemImage: "list.bullet").tag(ItemViewMode.list)
            Label("Gallery View", systemImage: "square.grid.2x2").tag(ItemViewMode.gallery)
        }
        .pickerStyle(.inline)
        .disabled(browser.showsTypes)
    }
}
