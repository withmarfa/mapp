import SwiftUI

/// The Lists page of Settings: how much each row says, what every list shows, and where an item opens.
struct ListsSettings: View {
    @AppStorage(ListKey.density) private var density = Density.standard
    @AppStorage(ListKey.openItemsIn) private var openItemsIn = ItemOpening.standard

    var body: some View {
        Form {
            Section("Density") {
                Picker("Density", selection: $density) {
                    ForEach(Density.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("ListsDensity")
            }
            Section("In Every List") {
                OrderOptions()
                Picker("Open Items In", selection: $openItemsIn) {
                    ForEach(ItemOpening.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("ListsOpenItemsIn")
            }
            .labelStyle(.titleOnly)
        }
        .settingsForm()
    }
}
