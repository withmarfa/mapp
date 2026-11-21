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

/// A shortcut at a row's trailing edge, the system has no recorder for, so it is the system's bordered button, 200 wide, with the
/// keys in it. A set one has a clear button; an empty one reads Record Shortcut; one being recorded reads Type Shortcut with a
/// gray focus ring; a refused one has the red ring, and the row's line says why. A click starts recording, the next key press is
/// handed to `record`, Escape stops, and Delete clears.
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
            Toggle(isOn: $byKeys) {
                Label("Search by Pressing a Shortcut", systemImage: "keyboard").labelStyle(.iconOnly)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Search by Pressing a Shortcut")
            .accessibilityIdentifier("ShortcutSearchByKeys")
            if byKeys {
                SettingsSearchField(prompt: String(localized: "Press a Shortcut"), text: .constant(pressed ?? ""), identifier: "ShortcutSearch")
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
