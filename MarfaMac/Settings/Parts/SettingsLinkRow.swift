import SwiftUI

/// A row that opens a page of its own: what it says, a value at the trailing edge (with a dot before it where it is a state) and a chevron. The whole row is the
/// button.
struct SettingsLinkRow: View {
    private let title: Text
    private let line: Text?
    private let lead: SettingsLead
    private let value: Text?
    private let dot: Color?
    private let titleGlyph: SettingsTextGlyph?
    private let lineGlyph: SettingsTextGlyph?
    private let valueGlyph: SettingsTextGlyph?
    private let lock: String?
    private let lines: Int?
    private let action: () -> Void

    init(
        verbatim title: String, line: String? = nil, lead: SettingsLead = .none, value: String? = nil, dot: Color? = nil,
        lines: Int? = 2, titleGlyph: SettingsTextGlyph? = nil, lineGlyph: SettingsTextGlyph? = nil, valueGlyph: SettingsTextGlyph? = nil, lock: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = Text(verbatim: title)
        self.line = line.map { Text(verbatim: $0) }
        self.lead = lead
        self.value = value.map { Text(verbatim: $0) }
        self.dot = dot
        self.lines = lines
        self.titleGlyph = titleGlyph
        self.lineGlyph = lineGlyph
        self.valueGlyph = valueGlyph
        self.lock = lock
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            SettingsRow(title: title, line: line, titleGlyph: titleGlyph, lineGlyph: lineGlyph, lead: rowLead, lines: lines) {
                if let lock {
                    SettingsLockedValue(text: lock)
                } else {
                    HStack(spacing: SettingsTokens.Metric.buttonGap) {
                        if let value {
                            HStack(spacing: SettingsTokens.Metric.dotGap) {
                                if let dot { SettingsStatusDot(color: dot) }
                                value.withSettingsGlyph(valueGlyph)
                                    .settingsFont(.title)
                                    .foregroundStyle(SettingsTokens.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        SettingsChevron()
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .containerValue(\.settingsRuleInset, lead.isNone ? SettingsTokens.Metric.inset : SettingsTokens.Metric.textInset)
    }

    private var rowLead: SettingsLead {
        guard lock != nil, case let .tile(symbol, tone) = lead else { return lead }
        return .custom(AnyView(SettingsTile(symbol: symbol, tone: tone).opacity(SettingsTokens.Metric.lockedTileOpacity)))
    }
}
