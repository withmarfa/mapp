#if DEBUG
import AppKit
import SwiftUI

/// The floating panel that lists every knob, grouped by area. Its text is for developers only, so it is not localized.
struct TuningPanel: View {
    static let windowID = "tuning"
    static let title = "Tuning"

    @State private var tuning = Tuning.shared

    var body: some View {
        VStack(spacing: 0) {
            if tuning.knobs.isEmpty {
                Text(verbatim: "No knobs yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    ForEach(groups, id: \.name) { group in
                        Section {
                            ForEach(group.knobs) { knob in control(for: knob) }
                        } header: {
                            Text(verbatim: group.name)
                        }
                    }
                }
                .formStyle(.grouped)
            }
            Divider()
            HStack {
                Spacer()
                Button { tuning.reset() } label: { Text(verbatim: "Reset") }
                Button { copy() } label: { Text(verbatim: "Copy") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 380)
        .frame(minHeight: 240, idealHeight: 420)
    }

    private var groups: [(name: String, knobs: [Knob])] {
        var order: [String] = []
        for knob in tuning.knobs where !order.contains(knob.group) { order.append(knob.group) }
        return order.map { name in (name, tuning.knobs.filter { $0.group == name }) }
    }

    @ViewBuilder
    private func control(for knob: Knob) -> some View {
        switch knob.kind {
        case .slider(let range, let step):
            let number = Binding(get: { tuning.number(knob) }, set: { tuning[knob] = .number($0) })
            LabeledContent {
                HStack {
                    Slider(value: number, in: range, step: step)
                    Text(verbatim: tuning[knob].text)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            } label: { Text(verbatim: knob.name) }
        case .toggle:
            Toggle(isOn: Binding(get: { tuning[knob] == .flag(true) }, set: { tuning[knob] = .flag($0) })) {
                Text(verbatim: knob.name)
            }
        case .picker(let options):
            Picker(selection: Binding(get: { tuning[knob].text }, set: { tuning[knob] = .option($0) })) {
                ForEach(options, id: \.self) { Text(verbatim: $0).tag($0) }
            } label: { Text(verbatim: knob.name) }
        }
    }

    private func copy() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tuning.report(build: build), forType: .string)
    }
}

/// The Developer menu, which exists only in Debug builds.
struct TuningCommands: Commands {
    /// A string variable, not a literal, so the String Catalog does not pick the title up.
    private let menuTitle = "Developer"
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu(menuTitle) {
            Button { openWindow(id: TuningPanel.windowID) } label: { Text(verbatim: "Show Tuning Panel") }
        }
    }
}
#endif
