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
    /// A type's or a source's mark, drawn as a plain symbol is.
    case mark(Image)
    /// An app, a source or a connector: a white tile with a hairline, holding a symbol or a mark in the secondary color.
    case well(AnyView)
    /// Anything else the row needs in the column, such as an app's picture.
    case custom(AnyView)

    /// A well holding one symbol.
    static func well(symbol: String) -> SettingsLead {
        .well(AnyView(Image(systemName: symbol)))
    }

    var isNone: Bool {
        if case .none = self { true } else { false }
    }
}

/// The hairline tile an app, a source, a connector or a webhook takes around what stands for it: a row's lead column by
/// default, or a head's large tile at `SettingsTokens.Metric.headTile`.
struct SettingsWell<Content: View>: View {
    var size: CGFloat = SettingsTokens.Metric.tile
    @ViewBuilder let content: Content

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsTokens.Metric.controlRadius, style: .continuous)
            .fill(SettingsTokens.card)
            .frame(width: size, height: size)
            .overlay { RoundedRectangle(cornerRadius: SettingsTokens.Metric.controlRadius, style: .continuous).strokeBorder(SettingsTokens.hairline, lineWidth: 1) }
            .overlay { content.font(.system(size: size * SettingsTokens.Metric.wellGlyph)).foregroundStyle(SettingsTokens.secondaryText) }
    }
}

/// The colored tile a page, place or key takes: `size` points square, with a white symbol.
struct SettingsTile: View {
    let symbol: String
    let tone: SettingsTokens.Tone
    var size: CGFloat = SettingsTokens.Metric.tile
    var isSidebar = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * SettingsTokens.Metric.tileRounding) }

    var body: some View {
        shape.fill(isSidebar ? tone.sidebarColor : tone.color)
            .frame(width: size, height: size)
            .overlay {
                SettingsTileGlyph(symbol: symbol, tileSize: size,
                                  proportion: isSidebar ? SettingsTokens.Metric.sidebarTileGlyph : SettingsTokens.Metric.tileGlyph)
                    .foregroundStyle(SettingsTokens.tileForeground)
            }
            .accessibilityHidden(true)
    }
}

/// A tile's symbol, fitted into a square so wide and tall symbols keep the same padding.
struct SettingsTileGlyph: View {
    let symbol: String
    let tileSize: CGFloat
    var proportion: CGFloat = SettingsTokens.Metric.tileGlyph

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.medium)
            .frame(width: tileSize * proportion, height: tileSize * proportion)
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
    private let lineGlyph: SettingsTextGlyph?
    private let error: String?
    private let lead: SettingsLead
    private let size: Size
    private let look: Look
    private let lines: Int?
    private let trailing: Trailing
    @Environment(\.settingsTextScale) private var scale
    @Environment(\.settingsUsesSheetControls) private var usesSheetControls

    init(
        title: Text, line: Text? = nil, lineGlyph: SettingsTextGlyph? = nil,
        error: String? = nil, lead: SettingsLead = .none, size: Size = .standard,
        look: Look = .normal, lines: Int? = 2, @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.line = line
        self.lineGlyph = lineGlyph
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
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .settingsFont(.title)
                        .lineLimit(scale < SettingsTokens.Metric.controlScaleForLarge ? 1 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .truncationMode(.tail)
                        .foregroundStyle(look == .off ? SettingsTokens.tertiaryText : SettingsTokens.primaryText)
                    if let error {
                        Text(verbatim: error)
                            .settingsFont(.line)
                            .foregroundStyle(SettingsTokens.errorRed)
                            .lineLimit(lines)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let line {
                        line.withSettingsGlyph(lineGlyph)
                            .settingsFont(.line)
                            .foregroundStyle(look == .off ? SettingsTokens.tertiaryText : SettingsTokens.secondaryText)
                            .lineLimit(lines)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, size == .standard ? SettingsTokens.Metric.rowTextPadding : 0)
                Spacer(minLength: 0)
                trailing
                    .environment(\.settingsCompactControls, !usesSheetControls)
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
            RoundedRectangle(cornerRadius: SettingsTokens.Metric.tile * SettingsTokens.Metric.tileRounding, style: .continuous)
                .fill(tone.color.opacity(0.18))
                .frame(width: SettingsTokens.Metric.tile, height: SettingsTokens.Metric.tile)
                .overlay { SettingsTileGlyph(symbol: symbol, tileSize: SettingsTokens.Metric.tile).foregroundStyle(tone.color) }
                .accessibilityHidden(true)
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 14)).foregroundStyle(SettingsTokens.secondaryText).accessibilityHidden(true)
        case .mark(let image):
            image.font(.system(size: 14)).foregroundStyle(SettingsTokens.secondaryText).accessibilityHidden(true)
        case .well(let view):
            SettingsWell { view }.accessibilityHidden(true)
        case .custom(let view):
            view
        }
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(title: Text, line: Text? = nil, lineGlyph: SettingsTextGlyph? = nil, error: String? = nil, lead: SettingsLead = .none, size: Size = .standard, look: Look = .normal, lines: Int? = 2) {
        self.init(title: title, line: line, lineGlyph: lineGlyph, error: error, lead: lead, size: size, look: look, lines: lines, trailing: { EmptyView() })
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
