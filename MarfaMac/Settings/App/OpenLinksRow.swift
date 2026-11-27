import AppKit
import SwiftUI

/// The Mac’s default app for `marfa://` links.
struct OpenLinksRow: View {
    let model: OpenLinksModel

    private var selected: LinkApp? { model.apps.first { $0.url == model.current } }

    var body: some View {
        SettingsRow(
            title: Text("Open Marfa links in"), line: model.apps.isEmpty ? Text("No app on this Mac opens Marfa links yet.") : nil,
            error: error, look: model.apps.isEmpty ? .off : .normal, lines: nil
        ) {
            SettingsPopUp(
                title: "Open Marfa links in", selection: selection, isError: model.refusal != nil,
                currentValueLabel: selected.map { Text(verbatim: $0.name) } ?? Text("None")
            ) {
                if model.apps.isEmpty { Text("None").tag(URL?.none) }
                ForEach(model.apps) { app in
                    Label { Text(verbatim: app.title) } icon: { Image(nsImage: app.icon) }.tag(URL?.some(app.url))
                }
            }
            .help(Text(verbatim: selected?.title ?? ""))
            .disabled(model.isChanging)
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
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
