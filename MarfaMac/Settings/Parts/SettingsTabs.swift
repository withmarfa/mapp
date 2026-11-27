import SwiftUI

/// The text tabs over a Settings page. A tab can carry the count of what it shows.
struct SettingsTabs<Value: Hashable>: View {
    struct Tab {
        let value: Value
        let title: LocalizedStringKey
        var count: Int?
    }

    let tabs: [Tab]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.tabGap) {
            ForEach(tabs, id: \.value) { tab in
                let selected = tab.value == selection
                Button {
                    selection = tab.value
                } label: {
                    HStack(spacing: SettingsTokens.Metric.dotGap) {
                        Text(tab.title).fontWeight(.medium)
                            .foregroundStyle(selected ? SettingsTokens.primaryText : SettingsTokens.secondaryText)
                        if let count = tab.count {
                            Text(count, format: .number).settingsFont(.small).monospacedDigit().foregroundStyle(SettingsTokens.secondaryText)
                        }
                    }
                    .settingsFont(.title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SettingsTokens.Metric.tabPadding)
                    .frame(minHeight: SettingsTokens.Metric.tabHeight)
                    .background(selected ? SettingsTokens.selection : .clear, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
