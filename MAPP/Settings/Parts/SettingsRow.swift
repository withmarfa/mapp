import SwiftUI

/// What stands in a row's lead column, which is 24 points wide, so every row's text starts at 52 and its rule at the text.
enum SettingsLead {
    case none
    /// A page, a place or a key: a colored tile with a white symbol.
    case tile(String, SettingsTokens.Tone)
    /// A problem: a pale tinted tile with a colored symbol.
    case tint(String, SettingsTokens.Tone)
    /// A plain symbol.
    case symbol(String)
    /// Anything else the row needs in the column, such as a type's mark or an app's picture.
    case custom(AnyView)

    var isNone: Bool {
        if case .none = self { true } else { false }
    }
}

/// The colored tile a page, place or key takes: `size` points square, with a white symbol.
struct SettingsTile: View {
    let symbol: String
    let tone: SettingsTokens.Tone
    var size: CGFloat = SettingsTokens.Metric.tile

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(tone.color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// A row in a section: a lead, a title with one line under it (two at most, never three), then one trailing edge. It is
/// 44 points tall, 56 with a line and 36 compact. A row that cannot change now is `off`, with its reason as its line; a
/// refused input is an `error`, which replaces the line with one line in the error red.
struct SettingsRow<Trailing: View>: View {
    enum Size { case standard, compact }
    enum Look { case normal, off }

    private let title: Text
    private let line: Text?
    private let error: String?
    private let lead: SettingsLead
    private let size: Size
    private let look: Look
    private let lines: Int?
    private let trailing: Trailing
    @Environment(\.settingsTextScale) private var scale

    init(
        title: Text, line: Text? = nil, error: String? = nil, lead: SettingsLead = .none, size: Size = .standard,
        look: Look = .normal, lines: Int? = 2, @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.line = line
        self.error = error
        self.lead = lead
        self.size = size
        self.look = look
        self.lines = lines
        self.trailing = trailing()
    }

    private var hasLine: Bool { line != nil || error != nil }

    private var minHeight: CGFloat {
        let base = switch size {
        case .compact: SettingsTokens.Metric.rowHeightCompact
        case .standard: hasLine ? SettingsTokens.Metric.rowHeightWithLine : SettingsTokens.Metric.rowHeight
        }
        return base * scale
    }

    var body: some View {
        HStack(alignment: .center, spacing: SettingsTokens.Metric.textInset - SettingsTokens.Metric.inset - SettingsTokens.Metric.leadColumn) {
            if !lead.isNone {
                leadView.frame(width: SettingsTokens.Metric.leadColumn)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    title
                        .settingsFont(.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(look == .off ? SettingsTokens.tertiaryText : SettingsTokens.primaryText)
                    if let error {
                        Text(verbatim: error)
                            .settingsFont(.line)
                            .foregroundStyle(SettingsTokens.errorRed)
                            .lineLimit(lines)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let line {
                        line
                            .settingsFont(.line)
                            .foregroundStyle(look == .off ? SettingsTokens.tertiaryText : SettingsTokens.secondaryText)
                            .lineLimit(lines)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                trailing
                    .disabled(look == .off)
            }
        }
        .padding(.horizontal, SettingsTokens.Metric.inset)
        .padding(.vertical, size == .compact ? 4 : 6)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .containerValue(\.settingsRuleInset, lead.isNone ? SettingsTokens.Metric.inset : SettingsTokens.Metric.textInset)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var leadView: some View {
        switch lead {
        case .none:
            EmptyView()
        case .tile(let symbol, let tone):
            SettingsTile(symbol: symbol, tone: tone)
        case .tint(let symbol, let tone):
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(tone.color.opacity(0.18))
                .frame(width: SettingsTokens.Metric.tile, height: SettingsTokens.Metric.tile)
                .overlay { Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(tone.color) }
                .accessibilityHidden(true)
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 14)).foregroundStyle(SettingsTokens.secondaryText).accessibilityHidden(true)
        case .custom(let view):
            view
        }
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(title: Text, line: Text? = nil, error: String? = nil, lead: SettingsLead = .none, size: Size = .standard, look: Look = .normal, lines: Int? = 2) {
        self.init(title: title, line: line, error: error, lead: lead, size: size, look: look, lines: lines, trailing: { EmptyView() })
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, line: LocalizedStringKey? = nil, error: String? = nil, lead: SettingsLead = .none, size: Size = .standard, look: Look = .normal, lines: Int? = 2) {
        self.init(title: Text(title), line: line.map { Text($0) }, error: error, lead: lead, size: size, look: look, lines: lines)
    }

    init(verbatim title: String, line: String? = nil, error: String? = nil, lead: SettingsLead = .none, size: Size = .standard, look: Look = .normal, lines: Int? = 2) {
        self.init(title: Text(verbatim: title), line: line.map { Text(verbatim: $0) }, error: error, lead: lead, size: size, look: look, lines: lines)
    }
}

extension SettingsRow {
    init(
        _ title: LocalizedStringKey, line: LocalizedStringKey? = nil, error: String? = nil, lead: SettingsLead = .none,
        size: Size = .standard, look: Look = .normal, lines: Int? = 2, @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(title: Text(title), line: line.map { Text($0) }, error: error, lead: lead, size: size, look: look, lines: lines, trailing: trailing)
    }

    /// A row whose words are already text, such as a name the server gave.
    init(
        verbatim title: String, line: String? = nil, error: String? = nil, lead: SettingsLead = .none, size: Size = .standard,
        look: Look = .normal, lines: Int? = 2, @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: Text(verbatim: title), line: line.map { Text(verbatim: $0) }, error: error, lead: lead, size: size, look: look,
            lines: lines, trailing: trailing)
    }
}
