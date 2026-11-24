import AppKit
import SwiftUI

/// A row that is one of a few choices that exclude each other: the system's radio button in the lead column, then the title
/// and its line, and at the trailing edge the one control that belongs to that choice. The whole row chooses it.
struct SettingsRadioRow<Trailing: View>: View {
    private let title: Text
    private let line: Text?
    private let isOn: Bool
    private let choose: () -> Void
    private let trailing: Trailing

    init(title: Text, line: Text? = nil, isOn: Bool, choose: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.line = line
        self.isOn = isOn
        self.choose = choose
        self.trailing = trailing()
    }

    var body: some View {
        SettingsRow(title: title, line: line, lead: .custom(AnyView(SettingsRadio(isOn: isOn, choose: choose).accessibilityLabel(title)))) {
            trailing
        }
        .contentShape(.rect)
        .onTapGesture(perform: choose)
    }
}

extension SettingsRadioRow where Trailing == EmptyView {
    init(title: Text, line: Text? = nil, isOn: Bool, choose: @escaping () -> Void) {
        self.init(title: title, line: line, isOn: isOn, choose: choose, trailing: { EmptyView() })
    }
}

/// One radio button. SwiftUI draws radio buttons only as a whole group, which can't put a control beside one choice.
private struct SettingsRadio: NSViewRepresentable {
    let isOn: Bool
    let choose: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(radioButtonWithTitle: "", target: context.coordinator, action: #selector(Coordinator.chosen))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.state = isOn ? .on : .off
        context.coordinator.choose = choose
    }

    func makeCoordinator() -> Coordinator { Coordinator(choose: choose) }

    final class Coordinator: NSObject {
        var choose: () -> Void

        init(choose: @escaping () -> Void) { self.choose = choose }

        @objc func chosen() { choose() }
    }
}
