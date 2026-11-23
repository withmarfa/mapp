import SwiftUI

/// A row that holds a long text under its title, as a description or a guidance does: the title, one line under it where
/// the row has one, and the text or its field across the whole card.
struct SettingsStackRow<Content: View>: View {
    private let title: Text
    private let line: Text?
    private let error: String?
    private let content: Content

    init(title: Text, line: Text? = nil, error: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.line = line
        self.error = error
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Metric.stackGap) {
            VStack(alignment: .leading, spacing: 2) {
                title.settingsFont(.title).foregroundStyle(SettingsTokens.primaryText)
                if let error {
                    Text(verbatim: error).settingsFont(.line).foregroundStyle(SettingsTokens.errorRed).fixedSize(horizontal: false, vertical: true)
                } else if let line {
                    line.settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(.horizontal, SettingsTokens.Metric.inset)
        .padding(.vertical, SettingsTokens.Metric.cardGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerValue(\.settingsRuleInset, SettingsTokens.Metric.inset)
        .accessibilityElement(children: .contain)
    }
}

/// A text that cannot be changed here, shown whole under its title: a plugin's guidance, or an ancestor's.
struct SettingsStackText: View {
    let text: String
    var isLocked = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsTokens.Metric.dotGap) {
            if isLocked {
                Image(systemName: "lock").font(.system(size: SettingsTokens.Metric.lockGlyph)).foregroundStyle(SettingsTokens.tertiaryText)
                    .accessibilityHidden(true)
            }
            Text(verbatim: text).settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// A text of several lines in the rounded field's look, with the count of characters against its limit under it.
struct SettingsTextArea: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var isError = false
    var lines = 4
    @Environment(\.settingsTextScale) private var scale

    var body: some View {
        TextField(title, text: $text, axis: .vertical)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .lineLimit(lines...(lines * 3))
            .font(SettingsTokens.font(.title, scale: scale))
            .settingsErrorRing(isError)
    }
}
