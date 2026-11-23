import SwiftUI

/// A row that opens a page of its own: what it says, a value at the trailing edge (with a dot before it where it is a state) and a chevron. The whole row is the
/// button.
struct SettingsLinkRow: View {
    private let title: Text
    private let line: Text?
    private let lead: SettingsLead
    private let value: Text?
    private let dot: Color?
    private let lines: Int?
    private let action: () -> Void

    init(verbatim title: String, line: String? = nil, lead: SettingsLead = .none, value: String? = nil, dot: Color? = nil, lines: Int? = 2, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.line = line.map { Text(verbatim: $0) }
        self.lead = lead
        self.value = value.map { Text(verbatim: $0) }
        self.dot = dot
        self.lines = lines
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            SettingsRow(title: title, line: line, lead: lead, lines: lines) {
                HStack(spacing: SettingsTokens.Metric.buttonGap) {
                    if let value {
                        HStack(spacing: SettingsTokens.Metric.dotGap) {
                            if let dot { SettingsStatusDot(color: dot) }
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
