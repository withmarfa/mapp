import SwiftUI

/// How the list's rows look: their style and whether they show a preview of the text and pictures. Each follows Settings
/// until the view or place chooses; a saved view's choices are kept on this Mac as they are made, and a place's last as
/// long as the window (`Browser.changeRows`). A switch shows what the list draws now, so it starts from Settings.
struct ViewPanelRows: View {
    let browser: Browser
    let panel: ViewPanel
    @AppStorage(ListKey.previewLines) private var settingsLines = ListKey.defaultPreviewLines
    @AppStorage(ListKey.showsPictures) private var settingsPictures = true

    var body: some View {
        let rows = browser.rows
        ViewPanelSection(title: "Rows", note: panel.purpose == .place ? nil : "This Mac") {
            InspectorBox {
                HStack {
                    Text("Row Style")
                    Spacer(minLength: 0)
                    Picker("Row Style", selection: Binding { rows.style } set: { value in browser.changeRows { $0.style = value } }) {
                        Text("As in Settings").tag(ListRowStyle?.none)
                        Divider()
                        ForEach(ListRowStyle.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityIdentifier("ViewPanelRowStyle")
                }
                switchRow(
                    "Show a Preview of the Text", id: "ViewPanelRowPreview",
                    isOn: Binding { rows.previewLines(settings: settingsLines) > 0 } set: { value in
                        browser.changeRows { $0.setShowsPreview(value, settings: settingsLines) }
                    })
                switchRow(
                    "Show Pictures", id: "ViewPanelRowPictures",
                    isOn: Binding { rows.showsPictures(settings: settingsPictures) } set: { value in
                        browser.changeRows { $0.setShowsPictures(value, settings: settingsPictures) }
                    })
            }
        }
    }

    private func switchRow(_ title: LocalizedStringKey, id: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 0)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityIdentifier(id)
        }
    }
}
