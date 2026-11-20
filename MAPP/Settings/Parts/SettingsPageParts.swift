import SwiftUI

/// A page's column: its sections in a column at most 620 points wide, centered, with more room either side as the window
/// widens. The page scrolls as one.
struct SettingsPageColumn<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                content
            }
            .frame(maxWidth: SettingsTokens.Metric.column, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SettingsTokens.page)
    }
}

/// A thing's head card: a large tile, its name, one line, and its actions at the trailing edge. It is the one card with
/// no name above it.
struct SettingsHead<Trailing: View>: View {
    private let symbol: String
    private let tone: SettingsTokens.Tone
    private let title: Text
    private let line: Text?
    private let trailing: Trailing
    @Environment(\.settingsTextScale) private var scale

    init(symbol: String, tone: SettingsTokens.Tone, title: Text, line: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.tone = tone
        self.title = title
        self.line = line
        self.trailing = trailing()
    }

    var body: some View {
        SettingsCard {
            HStack(spacing: 14) {
                SettingsTile(symbol: symbol, tone: tone, size: SettingsTokens.Metric.headTile)
                VStack(alignment: .leading, spacing: 2) {
                    title.settingsFont(.headTitle).lineLimit(1).accessibilityAddTraits(.isHeader)
                    if let line {
                        line.settingsFont(.line).foregroundStyle(SettingsTokens.secondaryText).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, SettingsTokens.Metric.inset)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 76 * scale, alignment: .leading)
        }
    }
}

extension SettingsHead where Trailing == EmptyView {
    init(symbol: String, tone: SettingsTokens.Tone, title: Text, line: Text? = nil) {
        self.init(symbol: symbol, tone: tone, title: title, line: line, trailing: { EmptyView() })
    }
}

/// One thing a problem row offers. Only actions that exist are offered.
struct SettingsProblemAction: Identifiable {
    let id = UUID()
    let title: Text
    var isDestructive = false
    /// The one shown as a button when there are more than two.
    var isPrimary = false
    let perform: () -> Void

    init(_ title: LocalizedStringKey, isDestructive: Bool = false, isPrimary: Bool = false, perform: @escaping () -> Void) {
        self.title = Text(title)
        self.isDestructive = isDestructive
        self.isPrimary = isPrimary
        self.perform = perform
    }

    init(verbatim title: String, isDestructive: Bool = false, isPrimary: Bool = false, perform: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.isDestructive = isDestructive
        self.isPrimary = isPrimary
        self.perform = perform
    }
}

/// A problem row: a tinted warning lead, what is wrong, and only the actions that exist: both as buttons where there are
/// two, and one button with a menu where there are more.
struct SettingsProblemRow: View {
    let title: Text
    var line: Text?
    var tone: SettingsTokens.Tone = .orange
    let actions: [SettingsProblemAction]
    /// A problem's words are told whole: an explanation is never cut to two lines.
    var lines: Int? = nil

    var body: some View {
        SettingsRow(title: title, line: line, lead: .tint("exclamationmark.triangle", tone), lines: lines) {
            HStack(spacing: 8) {
                if actions.count <= 2 {
                    ForEach(actions) { action in
                        SettingsButton(title: action.title, role: action.isDestructive ? .destructive : .normal, action: action.perform)
                    }
                } else {
                    let primary = actions.first(where: \.isPrimary) ?? actions[0]
                    SettingsButton(title: primary.title, role: primary.isDestructive ? .destructive : .normal, action: primary.perform)
                    SettingsMoreMenu {
                        ForEach(actions.filter { $0.id != primary.id }) { action in
                            Button(role: action.isDestructive ? .destructive : nil, action: action.perform) { action.title }
                        }
                    }
                }
            }
        }
    }
}

/// The words of a state: a symbol, a title, one line and an action, centered.
struct SettingsStateContent: View {
    let symbol: String
    let title: Text
    var line: Text?
    var action: (title: LocalizedStringKey, perform: () -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(SettingsTokens.tertiaryText)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            title.settingsFont(.stateTitle).multilineTextAlignment(.center)
            if let line {
                line
                    .settingsFont(.small)
                    .foregroundStyle(SettingsTokens.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                SettingsButton(action.title, action: action.perform).padding(.top, 10)
            }
        }
        .frame(maxWidth: 420)
        .accessibilityElement(children: .contain)
    }
}

/// What a page says in place of itself, centered in the space under the toolbar. It stands for a page the person may not
/// open, a server that is not answering, or a page with nothing to show.
struct SettingsPageState: View {
    let symbol: String
    let title: Text
    var line: Text?
    var action: (title: LocalizedStringKey, perform: () -> Void)?

    var body: some View {
        SettingsStateContent(symbol: symbol, title: title, line: line, action: action)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 80)
            .background(SettingsTokens.page)
    }
}

/// The empty card of a list with nothing in it yet: a symbol, a title, one line and an action.
struct SettingsEmptyCard: View {
    let symbol: String
    let title: Text
    var line: Text?
    var action: (title: LocalizedStringKey, perform: () -> Void)?

    var body: some View {
        SettingsCard {
            SettingsStateContent(symbol: symbol, title: title, line: line, action: action)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
        }
    }
}
