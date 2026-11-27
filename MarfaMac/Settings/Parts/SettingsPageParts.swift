import SwiftUI

/// A page's column: its sections in a column at most 620 points wide, centered, with more room either side as the window
/// widens. The page scrolls as one, unless `scrolls` is false: the sections then take only their height, above a state
/// that fills the rest.
struct SettingsPageColumn<Content: View>: View {
    var scrolls = true
    @ViewBuilder let content: Content

    var body: some View {
        if scrolls {
            ScrollView { column }
                .scrollBounceBehavior(.basedOnSize)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .background(SettingsTokens.page)
        } else {
            column.background(SettingsTokens.page)
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Metric.pageSpacing) {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    subviews[index].padding(.top, index == 0 ? subviews[index].containerValues.settingsFirstInset : 0)
                }
            }
        }
        .frame(maxWidth: SettingsTokens.Metric.column, alignment: .leading)
        .padding(.horizontal, SettingsTokens.Metric.pageSide)
        .padding(.top, SettingsTokens.Metric.pageTop)
        .padding(.bottom, scrolls ? SettingsTokens.Metric.pageBottom : 0)
        .frame(maxWidth: .infinity)
    }
}

/// A state that fills the page (`SettingsPageState`, a read in progress) under sections that keep their place, for
/// what holds whatever the state.
struct SettingsStandingState<Above: View, State: View>: View {
    @ViewBuilder let above: Above
    @ViewBuilder let state: State

    var body: some View {
        VStack(spacing: 0) {
            SettingsPageColumn(scrolls: false) { above }
            state
        }
    }
}

/// A thing's head card: a large tile, its name, one line, and its actions at the trailing edge. It has no name above it
/// on a thing's own page; on a list page that has one thing at its head, `name` puts a section's name above it.
struct SettingsHead<Trailing: View>: View {
    private let name: Text?
    private let lead: AnyView
    private let title: Text
    private let line: Text?
    private let trailing: Trailing
    @Environment(\.settingsTextScale) private var scale

    init(name: Text? = nil, symbol: String, tone: SettingsTokens.Tone, title: Text, line: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(
            name: name, lead: SettingsTile(symbol: symbol, tone: tone, size: SettingsTokens.Metric.headTile), title: title, line: line,
            trailing: trailing)
    }

    /// A head led by a well: the hairline tile of an app, a source or a webhook, at the large tile's size.
    init(name: Text? = nil, wellSymbol: String, title: Text, line: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(
            name: name, lead: SettingsWell(size: SettingsTokens.Metric.headTile) { Image(systemName: wellSymbol) }, title: title, line: line,
            trailing: trailing)
    }

    /// A head whose lead is anything that fits the large tile's place, such as a type's mark.
    init(name: Text? = nil, lead: some View, title: Text, line: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.name = name
        self.lead = AnyView(lead.frame(width: SettingsTokens.Metric.headTile, height: SettingsTokens.Metric.headTile))
        self.title = title
        self.line = line
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Metric.sectionGap) {
            if let name {
                name.settingsFont(.sectionName).accessibilityAddTraits(.isHeader)
                    .frame(minHeight: SettingsTokens.Metric.sectionHeader, alignment: .bottom)
                    .padding(.horizontal, SettingsTokens.Metric.inset)
            }
            card
        }
    }

    private var card: some View {
        SettingsCard {
            HStack(spacing: 14) {
                lead
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
    init(name: Text? = nil, wellSymbol: String, title: Text, line: Text? = nil) {
        self.init(name: name, wellSymbol: wellSymbol, title: title, line: line, trailing: { EmptyView() })
    }

    init(name: Text? = nil, symbol: String, tone: SettingsTokens.Tone, title: Text, line: Text? = nil) {
        self.init(name: name, symbol: symbol, tone: tone, title: title, line: line, trailing: { EmptyView() })
    }

    init(name: Text? = nil, lead: some View, title: Text, line: Text? = nil) {
        self.init(name: name, lead: lead, title: title, line: line, trailing: { EmptyView() })
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
    /// The lead's symbol: the warning triangle, or the lock for a refusal.
    var symbol = "exclamationmark.triangle"
    /// The tile the symbol sits in. With none, the symbol stands plain, as the lock does beside its explanation.
    var tone: SettingsTokens.Tone? = .orange
    let actions: [SettingsProblemAction]
    /// A problem's words are told whole: an explanation is never cut to two lines.
    var lines: Int? = nil

    var body: some View {
        SettingsRow(title: title, line: line, lead: tone.map { .tint(symbol, $0) } ?? .symbol(symbol), lines: lines) {
            HStack(spacing: SettingsTokens.Metric.buttonGap) {
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
    /// Where the words stand in a card (a list with nothing in it), which the boards draw tighter than a page's own state.
    var isInCard = false

    private typealias Gap = SettingsTokens.Metric.State

    var body: some View {
        VStack(spacing: isInCard ? Gap.cardSpacing : Gap.spacing) {
            Image(systemName: symbol)
                .font(.system(size: Gap.glyph, weight: .light))
                .foregroundStyle(SettingsTokens.tertiaryText)
                .padding(.bottom, isInCard ? Gap.cardSymbolGap : Gap.symbolGap)
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
                SettingsButton(action.title, action: action.perform).padding(.top, isInCard ? Gap.cardActionGap : Gap.actionGap)
            }
        }
        .frame(maxWidth: SettingsTokens.Metric.stateMeasure)
        .accessibilityElement(children: .contain)
    }
}

/// What a page says in place of itself: its words centered a third of the way down the pane, the toolbar's height counted. It stands
/// for a page the person may not open, a server that is not answering, or a page with nothing to show.
struct SettingsPageState: View {
    let symbol: String
    let title: Text
    var line: Text?
    var action: (title: LocalizedStringKey, perform: () -> Void)?

    var body: some View {
        GeometryReader { space in
            SettingsStateContent(symbol: symbol, title: title, line: line, action: action)
                .padding(.horizontal, SettingsTokens.Metric.pageSide)
                .position(x: space.size.width / 2, y: (space.size.height + space.safeAreaInsets.top) / 3 - space.safeAreaInsets.top + SettingsTokens.Metric.pageStateDrop)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsTokens.page)
    }
}

/// A row of buttons at the end of a page, at the trailing edge, for what the page's fields hold: Revert and Save for a
/// draft, or what sends or discards it. Buttons are regular size, since it is not inside a table.
struct SettingsBar<Content: View>: View {
    /// Which edge the buttons sit at: the trailing one for a draft's Revert and Save, the leading one for buttons under a
    /// card that act on the whole page.
    var edge: HorizontalEdge = .trailing
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.buttonGap) {
            if edge == .trailing { Spacer(minLength: 0) }
            content
            if edge == .leading { Spacer(minLength: 0) }
        }
        // The page's spacing puts a section apart from the next; the buttons belong to the card above.
        .padding(.top, SettingsTokens.Metric.barGap - SettingsTokens.Metric.pageSpacing)
    }
}

/// What fills the card of a list with nothing in it yet: a symbol, a title, one line and an action. It stands in a
/// section's card, which draws the border, so the card never holds a second one.
struct SettingsEmptyCard: View {
    let symbol: String
    let title: Text
    var line: Text?
    var action: (title: LocalizedStringKey, perform: () -> Void)?

    var body: some View {
        SettingsStateContent(symbol: symbol, title: title, line: line, action: action, isInCard: true)
            .padding(.vertical, SettingsTokens.Metric.emptyCardPadding)
            .frame(maxWidth: .infinity)
    }
}

/// Words both halves of Settings use.
enum SettingsWording {
    /// A server's address without its scheme, with its port where it has one.
    static func hostName(of address: URL) -> String {
        guard let host = address.host(percentEncoded: false) else { return address.absoluteString }
        return address.port.map { "\(host):\($0)" } ?? host
    }
}

/// A page heading with its address and actions at the trailing edge, without a card.
struct SettingsPageHeader<Trailing: View>: View {
    let name: String
    let address: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: SettingsTokens.Metric.tableColumnGap) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: name)
                    .settingsFont(.pageHeader)
                    .frame(minHeight: SettingsTokens.Metric.pageHeaderNameHeight)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: address).withSettingsGlyph(.link)
                    .settingsFont(.title)
                    .frame(minHeight: SettingsTokens.Metric.pageHeaderAddressHeight)
                    .foregroundStyle(SettingsTokens.secondaryText)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            trailing.fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, SettingsTokens.Metric.inset)
        .padding(.top, SettingsTokens.Metric.pageHeaderTop)
    }
}
