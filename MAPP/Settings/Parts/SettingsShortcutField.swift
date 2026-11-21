import AppKit
import SwiftUI

/// Takes the next key presses of the window ahead of its menus, which would otherwise answer a key such as ⌘N before a field
/// could read it. A recording or a search by keys holds one while it is on.
@MainActor
final class SettingsKeyMonitor {
    private var token: Any?

    /// Calls `handler` for each key and mouse press until `stop`. It answers whether it took the event, which then goes no
    /// further.
    func start(_ handler: @escaping (NSEvent) -> Bool) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            MainActor.assumeIsolated { handler(event) } ? nil : event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

extension NSEvent {
    /// A press of Escape, or of Delete with no modifier.
    var isEscape: Bool { type == .keyDown && keyCode == 53 }

    var isBareDelete: Bool {
        type == .keyDown && (keyCode == 51 || keyCode == 117) && modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }
}

/// A shortcut at a row's trailing edge: white, 200 by 28, the keys centered. A set one has a clear button; an empty one reads
/// Record Shortcut; one being recorded reads Type Shortcut with a gray focus ring; a refused one has the red ring, and the
/// row's line says why. A click starts recording, the next key press is handed to `record`, Escape stops, and Delete clears.
struct SettingsShortcutField: View {
    let title: LocalizedStringKey
    let keys: String?
    let isRecording: Bool
    var isError = false
    let startRecording: () -> Void
    let stopRecording: () -> Void
    let record: (NSEvent) -> Void
    let clear: () -> Void
    @State private var monitor = SettingsKeyMonitor()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsTokens.Metric.controlRadius, style: .continuous)
        Button(action: startRecording) {
            label
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if keys != nil, !isRecording {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .settingsFont(.small)
                        .foregroundStyle(SettingsTokens.tertiaryText)
                        .frame(width: SettingsTokens.Metric.controlHeight, height: SettingsTokens.Metric.controlHeight)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Shortcut")
            }
        }
        .frame(width: SettingsTokens.Metric.controlWidth, height: SettingsTokens.Metric.controlHeight)
        .background(SettingsTokens.field, in: shape)
        .overlay { shape.strokeBorder(SettingsTokens.hairline, lineWidth: 1) }
        .overlay { if isRecording { shape.stroke(SettingsTokens.focusRing, lineWidth: 3).padding(-1.5).allowsHitTesting(false) } }
        .settingsErrorRing(isError)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(keys ?? "")
        .onChange(of: isRecording, initial: true) { _, recording in
            if recording {
                monitor.start { event in
                    if event.type == .leftMouseDown {
                        stopRecording()
                        return false
                    }
                    if event.isEscape { stopRecording() } else if event.isBareDelete { clear(); stopRecording() } else { record(event) }
                    return true
                }
            } else {
                monitor.stop()
            }
        }
        .onDisappear { monitor.stop() }
    }

    @ViewBuilder private var label: some View {
        if isRecording {
            Text("Type Shortcut").settingsFont(.title).foregroundStyle(SettingsTokens.tertiaryText)
        } else if let keys {
            Text(verbatim: keys).settingsFont(.title).foregroundStyle(SettingsTokens.primaryText)
        } else {
            Text("Record Shortcut").settingsFont(.title).foregroundStyle(SettingsTokens.tertiaryText)
        }
    }
}

/// A small search at a list's trailing edge, with a keyboard button before it that changes what it searches by: the words of
/// a name, which are typed, or a shortcut, which is pressed. While the button is on, the field shows the keys pressed last,
/// and Escape turns it off.
struct SettingsShortcutSearch: View {
    @Binding var text: String
    @Binding var byKeys: Bool
    /// The keys pressed last, as written in a menu, while searching by keys.
    let pressed: String?
    let press: (NSEvent) -> Void
    @State private var monitor = SettingsKeyMonitor()

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.searchSpacing) {
            Button { byKeys.toggle() } label: {
                Image(systemName: "keyboard")
                    .settingsFont(.small)
                    .foregroundStyle(byKeys ? SettingsTokens.primaryText : SettingsTokens.secondaryText)
                    .frame(width: SettingsTokens.Metric.searchHeight, height: SettingsTokens.Metric.searchHeight)
                    .background(byKeys ? SettingsTokens.buttonFill : Color.clear, in: .rect(cornerRadius: SettingsTokens.Metric.searchRadius, style: .continuous))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Search by Pressing a Shortcut")
            .accessibilityLabel("Search by Pressing a Shortcut")
            .accessibilityAddTraits(byKeys ? .isSelected : [])
            .accessibilityIdentifier("ShortcutSearchByKeys")
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").settingsFont(.small).foregroundStyle(SettingsTokens.tertiaryText)
                if byKeys {
                    if let pressed {
                        Text(verbatim: pressed).settingsFont(.small).foregroundStyle(SettingsTokens.primaryText)
                    } else {
                        Text("Press a Shortcut").settingsFont(.small).foregroundStyle(SettingsTokens.tertiaryText)
                    }
                    Spacer(minLength: 0)
                } else {
                    TextField("Search Shortcuts", text: $text)
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .settingsFont(.small)
                        .accessibilityIdentifier("ShortcutSearch")
                }
            }
            .padding(.horizontal, SettingsTokens.Metric.searchInset)
            .frame(width: SettingsTokens.Metric.searchWidth, height: SettingsTokens.Metric.searchHeight)
            .background(SettingsTokens.buttonFill, in: .rect(cornerRadius: SettingsTokens.Metric.searchRadius, style: .continuous))
        }
        .onChange(of: byKeys, initial: true) { _, on in
            if on {
                monitor.start { event in
                    if event.type == .leftMouseDown { return false }
                    if event.isEscape { byKeys = false } else { press(event) }
                    return true
                }
            } else {
                monitor.stop()
            }
        }
        .onDisappear { monitor.stop() }
    }
}
