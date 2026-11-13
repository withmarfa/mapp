import SwiftUI

/// The Lists page of Settings: how much each row says, and what every list shows.
struct ListsSettings: View {
    @AppStorage(ListKey.density) private var density = Density.standard

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
            }
            .labelStyle(.titleOnly)
        }
        .settingsForm()
    }
}
