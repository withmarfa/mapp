import SwiftUI

/// A row that opens a page of its own: what it says, a value at the trailing edge and a chevron. The whole row is the
/// button.
struct SettingsLinkRow: View {
    private let title: Text
    private let line: Text?
    private let lead: SettingsLead
    private let value: Text?
    private let dot: Color?
    private let action: () -> Void

    init(verbatim title: String, line: String? = nil, lead: SettingsLead = .none, value: String? = nil, dot: Color? = nil, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.line = line.map { Text(verbatim: $0) }
        self.lead = lead
        self.value = value.map { Text(verbatim: $0) }
        self.dot = dot
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            SettingsRow(title: title, line: line, lead: lead) {
                HStack(spacing: 8) {
                    if let value {
                        HStack(spacing: 6) {
                            if let dot { Circle().fill(dot).frame(width: 7, height: 7).accessibilityHidden(true) }
                            value.settingsFont(.title).foregroundStyle(SettingsTokens.secondaryText).lineLimit(1)
                        }
                    }
                    SettingsChevron()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .containerValue(\.settingsRuleInset, lead.isNone ? SettingsTokens.Metric.inset : SettingsTokens.Metric.textInset)
    }
}
