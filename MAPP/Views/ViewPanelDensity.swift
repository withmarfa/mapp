import SwiftUI

/// How much each row of the list says: Standard or Compact. It follows Settings until the view or place chooses; a saved
/// view's choice is kept on this Mac as it is made, and a place's is kept for the place (`Browser.changeDensity`).
struct ViewPanelDensity: View {
    let browser: Browser
    let panel: ViewPanel

    var body: some View {
        let density = browser.density
        ViewPanelSection(title: "Density", note: panel.purpose == .place ? nil : "This Mac") {
            InspectorBox {
                HStack {
                    Text("Density")
                    Spacer(minLength: 0)
                    Picker("Density", selection: Binding { density } set: { browser.changeDensity($0) }) {
                        Text("As in Settings").tag(Density?.none)
                        Divider()
                        ForEach(Density.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityIdentifier("ViewPanelDensity")
                }
            }
        }
    }
}
