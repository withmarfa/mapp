import SwiftUI

/// The last row of a card that holds a list: it adds one more, as "New Key…" does. Adding is never a button in a
/// section's header. A row that cannot add now is `off`, with its reason as its line and, where the person can change
/// that, an action in the trailing edge.
struct SettingsAddRow: View {
    private let title: Text
    private let line: Text?
    private let isOff: Bool
    private let action: () -> Void
    private let remedy: (title: LocalizedStringKey, perform: () -> Void)?

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = Text(title)
        line = nil
        isOff = false
        self.action = action
        remedy = nil
    }

    /// A row that can't add now: `line` says why, and `remedy` is what the person can do about it.
    init(off title: LocalizedStringKey, line: LocalizedStringKey, remedy: (title: LocalizedStringKey, perform: () -> Void)? = nil) {
        self.title = Text(title)
        self.line = Text(line)
        isOff = true
        action = {}
        self.remedy = remedy
    }

    var body: some View {
        if isOff {
            SettingsRow(title: title, line: line, lead: .symbol("plus"), look: .off) {
                if let remedy { SettingsButton(remedy.title, action: remedy.perform).disabled(false) }
            }
        } else {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium)).accessibilityHidden(true)
                    title
                    Spacer(minLength: 0)
                }
                .settingsFont(.title)
                .foregroundStyle(SettingsTokens.secondaryText)
                .padding(.horizontal, SettingsTokens.Metric.inset)
                .frame(maxWidth: .infinity, minHeight: SettingsTokens.Metric.rowHeightCompact, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .containerValue(\.settingsRuleInset, SettingsTokens.Metric.inset)
        }
    }
}

/// The last row of a card that adds one of several things, chosen from a menu, such as a type to give an exception.
struct SettingsAddMenu<Items: View>: View {
    private let title: LocalizedStringKey
    private let items: Items

    init(_ title: LocalizedStringKey, @ViewBuilder items: () -> Items) {
        self.title = title
        self.items = items()
    }

    var body: some View {
        Menu {
            items
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11, weight: .medium)).accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 0)
            }
            .settingsFont(.title)
            .foregroundStyle(SettingsTokens.secondaryText)
            .padding(.horizontal, SettingsTokens.Metric.inset)
            .frame(maxWidth: .infinity, minHeight: SettingsTokens.Metric.rowHeightCompact, alignment: .leading)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .containerValue(\.settingsRuleInset, SettingsTokens.Metric.inset)
    }
}
