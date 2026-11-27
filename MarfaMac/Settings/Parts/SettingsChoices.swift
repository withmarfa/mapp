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

    private typealias Metric = SettingsTokens.Metric

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: Metric.choiceRadius, style: .continuous)
        let ringOutset = Metric.choiceRingGap + Metric.choiceRingWidth
        HStack(alignment: .top, spacing: Metric.choiceGap) {
            ForEach(choices) { choice in
                let isSelected = selection == choice.value
                Button { selection = choice.value } label: {
                    VStack(spacing: Metric.choiceTitleGap) {
                        // The tile's shape alone sets its size, so every tile in a row is the same height whatever its
                        // picture holds.
                        Color.clear
                            .aspectRatio(Metric.choiceAspect, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .topLeading) { choice.picture }
                            .clipShape(outline)
                            .overlay {
                                outline.strokeBorder(SettingsTokens.choiceEdge, lineWidth: Metric.choiceEdgeWidth)
                                    .allowsHitTesting(false)
                            }
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: Metric.choiceRadius + ringOutset, style: .continuous)
                                        .strokeBorder(SettingsTokens.choiceSelectionRing, lineWidth: Metric.choiceRingWidth)
                                        .padding(-ringOutset)
                                        .allowsHitTesting(false)
                                }
                            }
                        choice.title.settingsFont(.small).fontWeight(isSelected ? .semibold : .regular)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            ForEach(0..<max(0, (columns ?? choices.count) - choices.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
            }
        }
        .padding([.top, .horizontal], Metric.inset)
        .padding(.bottom, Metric.choiceBottom)
    }
}

struct SettingsIconChoices<Value: Hashable>: View {
    struct Choice: Identifiable {
        let value: Value
        let asset: String
        let title: Text
        var id: Value { value }
    }

    let choices: [Choice]
    @Binding var selection: Value
    let title: LocalizedStringKey

    private typealias Metric = SettingsTokens.Metric

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: Metric.controlRadius)
        HStack(spacing: Metric.iconChoiceSpacing) {
            ForEach(choices) { choice in
                Button { selection = choice.value } label: {
                    Image(choice.asset)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(Metric.iconChoiceScale)
                        .frame(width: Metric.tile, height: Metric.tile)
                        .overlay {
                            if choice.value == selection {
                                outline.strokeBorder(SettingsTokens.secondaryText, lineWidth: Metric.tileEdgeWidth)
                                    .padding(-Metric.iconChoiceRingOutset)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(choice.title)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(choice.value == selection ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}
