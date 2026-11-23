import SwiftUI

/// View Options > Properties: a tick for each property the layout can show, then Use Layouts once the list is changed, and
/// Edit Layouts…. The View menu and the toolbar hold the same menu. A menu closes after each tick: SwiftUI's
/// `menuActionDismissBehavior(.disabled)` is unavailable on macOS, so Edit View's Properties section is where several
/// are ticked at once.
struct PropertiesMenu: View {
    @CurrentLibrary private var library
    @Bindable var browser: Browser

    var body: some View {
        let offered = browser.offeredProperties(in: library).filter { $0.content != .title }
        Menu("Properties", systemImage: "list.bullet.rectangle") {
            ForEach(offered) { column in
                Toggle(column.label, isOn: Binding { browser.showsColumn(column) } set: { browser.setColumn(column, shown: $0) })
            }
            Divider()
            if browser.properties.isChanged {
                Button("Use Layouts", systemImage: "arrow.uturn.backward") { browser.useLayouts() }
                    .accessibilityIdentifier("UseLayoutsMenuItem")
            }
            EditLayoutsCommand(types: browser.layoutTypes(in: library)) { browser.showLayouts(of: $0) }
        }
        .accessibilityIdentifier("ViewOptionsProperties")
    }
}

/// Edit Layout of Events… for a place of one type, or Edit Layouts… with a menu of its types for several, each opening
/// Settings > Layouts at that type's page. Nothing for a place with no type.
struct EditLayoutsCommand: View {
    let types: [ItemTypeInfo]
    let open: (ItemTypeInfo) -> Void

    var body: some View {
        if types.count == 1, let type = types.first {
            Button("Edit Layout of \(type.plural)…", systemImage: "slider.horizontal.3") { open(type) }
                .accessibilityIdentifier("EditLayoutsCommand")
        } else if types.count > 1 {
            Menu("Edit Layouts…", systemImage: "slider.horizontal.3") {
                ForEach(types) { type in Button(type.plural) { open(type) } }
            }
            .accessibilityIdentifier("EditLayoutsCommand")
        }
    }
}
