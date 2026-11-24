import AppKit
import SwiftUI

/// Open Marfa Links In: the app macOS opens a `marfa://` link with. It needs no Marfa and no permission, so the Apps page
/// shows it even where its own state (a missing permission, no copy open) stands in place of the apps.
struct OpenLinksSection: View {
    @State private var model = OpenLinksModel()

    var body: some View {
        SettingsSection("On This Mac") {
            SettingsRow(
                title: Text("Open Marfa Links In"), line: line, error: error, look: model.apps.isEmpty ? .off : .normal
            ) {
                SettingsPopUp(title: "Open Marfa Links In", selection: selection, isError: model.refusal != nil) {
                    if model.apps.isEmpty {
                        Text("None").tag(URL?.none)
                    }
                    ForEach(model.apps) { app in
                        Label { Text(verbatim: app.title) } icon: { Image(nsImage: app.icon) }.tag(URL?.some(app.url))
                    }
                }
            }
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }

    private var line: Text {
        model.apps.isEmpty ? Text("No app on this Mac opens Marfa links yet.") : Text("Where a link to an item opens.")
    }

    private var error: String? {
        guard let refusal = model.refusal else { return nil }
        guard let kept = refusal.keptTitle else { return String(localized: "Couldn’t change it.") }
        return String(localized: "Couldn’t change it. Links still open in \(kept).")
    }

    /// What macOS holds. A choice is sent, and the pop-up moves only when the read-back shows macOS took it.
    private var selection: Binding<URL?> {
        Binding {
            model.current
        } set: { chosen in
            guard let chosen else { return }
            Task { await model.choose(chosen) }
        }
    }
}
