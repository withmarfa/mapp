import SwiftUI

/// Choices drawn as pictures filling a section's card, for a look the person should see, such as a theme or a row style.
/// The chosen one takes a gray ring, never the accent.
struct ChoiceTiles<Value: Hashable>: View {
    struct Choice: Identifiable {
        let value: Value
        let title: Text
        let picture: AnyView
        var id: Value { value }
    }

    let choices: [Choice]
    @Binding var selection: Value
    /// How many tiles the card has room for, where that is more than there are choices: the tiles keep their size and the
    /// empty places stay empty, so two row styles are not stretched to fill the card.
    var columns: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(choices) { choice in
                Button { selection = choice.value } label: {
                    VStack(spacing: 6) {
                        choice.picture
                            .frame(maxWidth: .infinity)
                            .aspectRatio(SettingsTokens.Metric.choiceAspect, contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        selection == choice.value ? SettingsTokens.primaryText.opacity(0.55) : SettingsTokens.hairline,
                                        lineWidth: selection == choice.value ? 2 : 1)
                            }
                        choice.title.settingsFont(.small).fontWeight(selection == choice.value ? .semibold : .regular)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == choice.value ? .isSelected : [])
            }
            ForEach(0..<max(0, (columns ?? choices.count) - choices.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
            }
        }
        .padding(SettingsTokens.Metric.inset)
    }
}

/// The tile of a row style: a small list in the density it names. Standard has a title and a quieter line under each row,
/// and Compact a title alone, so more rows fit.
struct SettingsRowStylePicture: View {
    let isCompact: Bool

    private typealias Metric = SettingsTokens.Metric
    private typealias Preview = SettingsTokens.RowPreview

    var body: some View {
        GeometryReader { space in
            VStack(alignment: .leading, spacing: Metric.rowPreviewGap) {
                ForEach(0..<(isCompact ? 5 : 3), id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Metric.rowPreviewInner) {
                        bar(Preview.title, share: Metric.rowPreviewTitle, in: space.size.width)
                        if !isCompact { bar(Preview.line, share: Metric.rowPreviewLine, in: space.size.width) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Metric.rowPreviewPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Preview.page)
        }
    }

    private func bar(_ color: Color, share: CGFloat, in width: CGFloat) -> some View {
        Capsule().fill(color).frame(width: (width - Metric.rowPreviewPadding * 2) * share, height: Metric.rowPreviewBar)
    }
}
