import AppKit
import SwiftUI

/// The Mac’s default app for `marfa://` links.
struct OpenLinksRow: View {
    let model: OpenLinksModel

    var body: some View {
        SettingsRow(
            title: Text("Open Marfa links in"), line: model.apps.isEmpty ? Text("No app on this Mac opens Marfa links yet.") : nil,
            error: error, look: model.apps.isEmpty ? .off : .normal, lines: nil
        ) {
            OpenLinksPopUp(apps: model.apps, selection: selection, isError: model.refusal != nil)
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

/// Shows the app’s short name in the control and the full names, including disambiguating paths, in its menu.
private struct OpenLinksPopUp: View {
    let apps: [LinkApp]
    @Binding var selection: URL?
    let isError: Bool
    @Environment(\.settingsTextScale) private var scale

    private var selected: LinkApp? { apps.first { $0.url == selection } }

    var body: some View {
        Picker("Open Marfa links in", selection: $selection) {
            if apps.isEmpty { Text("None").tag(URL?.none) }
            ForEach(apps) { app in
                Label { Text(verbatim: app.title) } icon: { Image(nsImage: app.icon) }.tag(URL?.some(app.url))
            }
        } currentValueLabel: {
            if let selected {
                Text(verbatim: selected.name).lineLimit(1).truncationMode(.middle)
            } else {
                Text("None")
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .settingsControlSize()
        .buttonSizing(.flexible)
        .frame(width: SettingsTokens.Metric.popUpMinimumWidth * max(1, scale))
        .settingsErrorRing(isError)
        .help(Text(verbatim: selected?.title ?? ""))
    }
}
