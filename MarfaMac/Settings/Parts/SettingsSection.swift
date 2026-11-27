import SwiftUI

extension ContainerValues {
    /// How much more room the page's column leaves above this part when it is the first on the page: a section with a name
    /// and a line sits lower than one with a name alone (`SettingsTokens.Metric.firstHeaderWithLineInset`).
    @Entry var settingsFirstInset: CGFloat = 0

    /// Where the rule above the next row starts: at the row's text, which sits after its lead, if it has one.
    @Entry var settingsRuleInset: CGFloat = SettingsTokens.Metric.inset
}

/// A named group of rows in one card: its name outside the card, a line under the name, the rows divided by rules that
/// start at their text, and a footer under the card. Every section is named, except a thing's head card
/// (`SettingsHead`). Put an add button, choices or a filter at the name's trailing edge (`accessory`).
struct SettingsSection<Content: View, Accessory: View>: View {
    private let name: Text?
    private let line: Text?
    private let footer: Text?
    private let accessory: Accessory
    private let content: Content
    @Environment(\.settingsSectionInset) private var inset
    @Environment(\.settingsUsesSheetControls) private var usesSheetControls

    init(
        name: Text?, line: Text? = nil, footer: Text? = nil,
        @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content
    ) {
        self.name = name
        self.line = line
        self.footer = footer
        self.accessory = accessory()
        self.content = content()
    }

    init(
        _ name: LocalizedStringKey, line: LocalizedStringKey? = nil, footer: LocalizedStringKey? = nil,
        @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content
    ) {
        self.init(name: Text(name), line: line.map { Text($0) }, footer: footer.map { Text($0) }, accessory: accessory, content: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Metric.sectionGap) {
            if name != nil || line != nil {
                VStack(alignment: .leading, spacing: SettingsTokens.Metric.rowTextPadding) {
                    HStack(spacing: SettingsTokens.Metric.tableColumnGap) {
                        if let name {
                            name.settingsFont(.sectionName).accessibilityAddTraits(.isHeader)
                        }
                        Spacer(minLength: 0)
                        accessory.environment(\.settingsCompactControls, !usesSheetControls)
                    }
                    if let line {
                        line.settingsFont(.sectionLine).foregroundStyle(SettingsTokens.secondaryText)
                    }
                }
                .frame(minHeight: SettingsTokens.Metric.sectionHeader, alignment: .bottom)
                .padding(.horizontal, inset)
            }
            SettingsCard(content: { content })
            if let footer {
                footer
                    .modifier(SettingsFooterText())
                    .padding(.horizontal, inset)
            }
        }
        .containerValue(\.settingsFirstInset, firstInset)
    }

    private var firstInset: CGFloat { line != nil ? SettingsTokens.Metric.firstHeaderWithLineInset : 0 }
}

extension SettingsSection where Accessory == EmptyView {
    init(_ name: LocalizedStringKey, line: LocalizedStringKey? = nil, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.init(name: Text(name), line: line.map { Text($0) }, footer: footer.map { Text($0) }, accessory: { EmptyView() }, content: content)
    }

    init(name: Text?, line: Text? = nil, footer: Text? = nil, @ViewBuilder content: () -> Content) {
        self.init(name: name, line: line, footer: footer, accessory: { EmptyView() }, content: content)
    }
}

/// The white card with a hairline that holds a section's rows, with a rule between each pair, drawn inside the lower row. A thing's head card and a
/// table use it on their own.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: SettingsTokens.Metric.cardRadius, style: .continuous)
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { index in
                    // The rule sits inside the row's top edge, so a row is its own height, divider included.
                    rows[index]
                        .overlay(alignment: .top) {
                            if index > 0 {
                                Rectangle()
                                    .fill(SettingsTokens.rule)
                                    .frame(height: SettingsTokens.Metric.cardRuleWidth)
                                    .padding(.leading, rows[index].containerValues.settingsRuleInset)
                                    .padding(.trailing, SettingsTokens.Metric.inset)
                                    .accessibilityHidden(true)
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(outline)
        .background {
            outline.fill(SettingsTokens.card)
                .shadow(color: SettingsTokens.cardShadow, radius: SettingsTokens.Metric.cardShadowRadius, y: SettingsTokens.Metric.cardShadowDrop)
        }
        .overlay { outline.strokeBorder(SettingsTokens.cardEdge, lineWidth: SettingsTokens.Metric.cardEdgeWidth).allowsHitTesting(false) }
    }
}

/// A line of text under the sections, as a note.
struct SettingsNote: View {
    let text: Text

    init(_ text: LocalizedStringKey) { self.text = Text(text) }
    init(verbatim text: String) { self.text = Text(verbatim: text) }

    var body: some View {
        text
            .modifier(SettingsFooterText())
            .padding(.horizontal, SettingsTokens.Metric.inset)
    }
}

private struct SettingsFooterText: ViewModifier {
    @Environment(\.settingsTextScale) private var scale

    func body(content: Content) -> some View {
        content
            .font(SettingsTokens.font(.footer, scale: scale))
            .lineHeight(.exact(points: SettingsTokens.Metric.footerLineHeight * scale))
            .foregroundStyle(SettingsTokens.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
