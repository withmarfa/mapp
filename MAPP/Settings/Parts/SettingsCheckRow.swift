import SwiftUI

/// A row that chooses one of several: a checkbox in the lead column, then the title, with one line under it where it needs
/// one. The whole row is the control, and the system draws the checkbox. A list of these is how many things are chosen
/// together, and a first row that stands for all of them is "All Events"-style.
struct SettingsCheckRow: View {
    private let title: Text
    private let line: Text?
    private let error: String?
    @Binding private var isOn: Bool

    init(title: Text, line: Text? = nil, error: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.line = line
        self.error = error
        _isOn = isOn
    }

    init(verbatim title: String, line: String? = nil, error: String? = nil, isOn: Binding<Bool>) {
        self.init(title: Text(verbatim: title), line: line.map { Text(verbatim: $0) }, error: error, isOn: isOn)
    }

    var body: some View {
        SettingsRow(
            title: title, line: line, error: error,
            lead: .custom(AnyView(Toggle(isOn: $isOn) { title }.labelsHidden().toggleStyle(.checkbox))), size: .compact
        )
        .contentShape(.rect)
        .onTapGesture { isOn.toggle() }
    }
}

/// The last row of a card that shows part of a list: "6 More", which shows the rest.
struct SettingsShowMoreRow: View {
    let title: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                title
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).accessibilityHidden(true)
            }
            .settingsFont(.title)
            .foregroundStyle(SettingsTokens.secondaryText)
            .frame(maxWidth: .infinity, minHeight: SettingsTokens.Metric.rowHeightCompact)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .containerValue(\.settingsRuleInset, SettingsTokens.Metric.inset)
    }
}
