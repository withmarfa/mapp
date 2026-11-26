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

/// The system has no shortcut recorder. This control takes key presses before the menus can handle them.
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
        Button(action: startRecording) { label.frame(maxWidth: .infinity) }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: SettingsTokens.Metric.controlRadius))
            .buttonSizing(.flexible)
            .controlSize(.large)
            .overlay(alignment: .trailing) {
                if keys != nil, !isRecording {
                    Button(action: clear) {
                        Image(systemName: "xmark.circle.fill")
                            .settingsFont(.small)
                            .foregroundStyle(SettingsTokens.tertiaryText)
                            .padding(.horizontal, 6)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Shortcut")
                }
            }
            .frame(width: SettingsTokens.Metric.controlWidth)
            .overlay { if isRecording { shape.stroke(SettingsTokens.focusRing, lineWidth: ChipLooks.defaults.focusRingWidth).padding(-ChipLooks.defaults.focusRingWidth / 2).allowsHitTesting(false) } }
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if isRecording { stopRecording() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if isRecording { stopRecording() }
        }
        .onDisappear {
            monitor.stop()
            if isRecording { stopRecording() }
        }
    }

    @ViewBuilder private var label: some View {
        if isRecording {
            Text("Type Shortcut").foregroundStyle(.secondary)
        } else if let keys {
            Text(verbatim: keys)
        } else {
            Text("Record Shortcut").foregroundStyle(.secondary)
        }
    }
}

/// Lets people search by pressing a shortcut as well as by typing its name.
struct SettingsShortcutSearch: View {
    @Binding var text: String
    @Binding var byKeys: Bool
    /// The keys pressed last, as written in a menu, while searching by keys.
    let pressed: String?
    let clearPressed: () -> Void
    let press: (NSEvent) -> Void
    @State private var monitor = SettingsKeyMonitor()

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.searchSpacing) {
            Toggle(isOn: $byKeys) {
                Label("Search by Pressing a Shortcut", systemImage: "keyboard").labelStyle(.iconOnly)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Search by Pressing a Shortcut")
            .accessibilityIdentifier("ShortcutSearchByKeys")
            if byKeys {
                SettingsSearchField(
                    prompt: String(localized: "Press a Shortcut"),
                    text: .constant(pressed ?? ""), identifier: "ShortcutSearch", onClear: clearPressed)
            } else {
                SettingsSearchField(prompt: String(localized: "Search Shortcuts"), text: $text, identifier: "ShortcutSearch")
            }
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in byKeys = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in byKeys = false }
        .onDisappear {
            monitor.stop()
            byKeys = false
        }
    }
}
