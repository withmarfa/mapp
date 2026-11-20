import SwiftUI

extension ContainerValues {
    /// Where the rule above the next row starts: at the row's text, which sits after its lead, if it has one.
    @Entry var settingsRuleInset: CGFloat = SettingsTokens.Metric.inset
}

/// A named group of rows in one card: its name outside the card, a line under the name, the rows divided by rules that
/// start at their text, and a footer under the card. Every section is named, except a thing's head card
/// (`SettingsHead`). A table's filter and search sit at the name's trailing edge (`accessory`), and nothing else.
struct SettingsSection<Content: View, Accessory: View>: View {
    private let name: Text?
    private let line: Text?
    private let footer: Text?
    private let accessory: Accessory
    private let content: Content
    @Environment(\.settingsTextScale) private var scale

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if name != nil || line != nil {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let name {
                            name.settingsFont(.sectionName).accessibilityAddTraits(.isHeader)
                        }
                        if let line {
                            line.settingsFont(.sectionLine).foregroundStyle(SettingsTokens.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                    accessory
                }
                .padding(.horizontal, SettingsTokens.Metric.inset)
                .padding(.bottom, 2)
            }
            SettingsCard(content: { content })
            if let footer {
                footer
                    .settingsFont(.footer)
                    .foregroundStyle(SettingsTokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SettingsTokens.Metric.inset)
                    .padding(.top, 2)
            }
        }
    }
}

extension SettingsSection where Accessory == EmptyView {
    init(_ name: LocalizedStringKey, line: LocalizedStringKey? = nil, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.init(name: Text(name), line: line.map { Text($0) }, footer: footer.map { Text($0) }, accessory: { EmptyView() }, content: content)
    }

    init(name: Text?, line: Text? = nil, footer: Text? = nil, @ViewBuilder content: () -> Content) {
        self.init(name: name, line: line, footer: footer, accessory: { EmptyView() }, content: content)
    }
}

/// The white card with a hairline that holds a section's rows, with a rule between each pair. A thing's head card and a
/// table use it on their own.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { index in
                    if index > 0 {
                        Rectangle()
                            .fill(SettingsTokens.rule)
                            .frame(height: 1)
                            .padding(.leading, rows[index].containerValues.settingsRuleInset)
                            .padding(.trailing, SettingsTokens.Metric.inset)
                            .accessibilityHidden(true)
                    }
                    rows[index]
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsTokens.card, in: .rect(cornerRadius: SettingsTokens.Metric.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTokens.Metric.cardRadius, style: .continuous)
                .strokeBorder(SettingsTokens.hairline, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: SettingsTokens.Metric.cardRadius, style: .continuous))
    }
}

/// A line of text under the sections, as a note.
struct SettingsNote: View {
    let text: Text

    init(_ text: LocalizedStringKey) { self.text = Text(text) }
    init(verbatim text: String) { self.text = Text(verbatim: text) }

    var body: some View {
        text
            .settingsFont(.footer)
            .foregroundStyle(SettingsTokens.secondaryText)
            .padding(.horizontal, SettingsTokens.Metric.inset)
            .fixedSize(horizontal: false, vertical: true)
    }
}
