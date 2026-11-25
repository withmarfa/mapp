import AppKit
import SwiftUI

/// The top row of a list: the place's title with its count on one baseline, the control that says All Items, Library or
/// Feed, and the place's views as pills. The views have a row of their own until the list scrolls, and then stand beside
/// the title. The row folds by the room it has (`TopRowFold`), and searching leaves the current view as one pill.
/// Drawn in the content under the window's hidden title (`TopRowHost`), so every place and layout has the same one.
struct TopRowTitleLine: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @StoredOrder private var order
    let browser: Browser
    let content: TopRowContent
    /// Whether the views stand beside the title. Otherwise they have a row of their own (`TopRowViewsLine`), or the place
    /// has one view and no row of views.
    let showsViews: Bool
    /// Whether the title opens the sidebar's rows, as it does with the sidebar closed.
    let opensPlaces: Bool
    /// Whether the window is at its smallest, where the views are the one pill beside the title.
    let isSmall: Bool

    var body: some View {
        let pieces = TopRowPieces(browser: browser, content: content, library: library, order: order)
        ViewThatFits(in: .horizontal) {
            ForEach(Array(folds.enumerated()), id: \.offset) { _, fold in
                HStack(spacing: 14) {
                    pieces.title(opensPlaces: opensPlaces, libraries: libraries)
                    if fold.scope { pieces.scopeControl }
                    if showsViews { pieces.views(fold) } else { Spacer(minLength: 0) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Beside the title every step of the fold is in play. Alone, the title has only the control to give up, and only
    /// while it says the default.
    private var folds: [TopRowFold] {
        if showsViews {
            let steps = TopRowFold.steps(
                viewCount: content.views.count, hasPlaces: !content.places.isEmpty, offersScope: content.showsScope,
                scopeIsDefault: content.isDefaultScope, restsBelow: false)
            // The field takes the room while searching, and the smallest window has none to spare: the views are the one
            // pill whatever there is.
            return browser.isSearchExpanded || isSmall ? Array(steps.suffix(1)) : steps
        }
        var folds = [TopRowFold(scope: content.showsScope, places: .none, shown: nil)]
        if content.showsScope, content.isDefaultScope { folds.append(TopRowFold(scope: false, places: .none, shown: nil)) }
        return folds
    }
}

/// The views on a row of their own under the title, until the list has scrolled.
struct TopRowViewsLine: View {
    @CurrentLibrary private var library
    @StoredOrder private var order
    let browser: Browser
    let content: TopRowContent

    var body: some View {
        let pieces = TopRowPieces(browser: browser, content: content, library: library, order: order)
        let steps = TopRowFold.steps(
            viewCount: content.views.count, hasPlaces: !content.places.isEmpty, offersScope: false,
            scopeIsDefault: false, restsBelow: true)
        ViewThatFits(in: .horizontal) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, fold in pieces.views(fold) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The parts a row is made of, for the title's line and the views' line.
@MainActor
struct TopRowPieces {
    let browser: Browser
    let content: TopRowContent
    let library: any ItemLibrary
    let order: ItemOrder

    // MARK: Title

    func title(opensPlaces: Bool, libraries: Libraries) -> some View {
        TopRowTitle(
            title: content.title, countText: content.countText, label: content.titleLabel,
            menu: opensPlaces ? PlacesMenu.make(library: library, layout: libraries.sidebarLayout) : nil,
            browser: browser, order: order)
    }

    // MARK: The control after the count

    var scopeControl: some View {
        Menu {
            ForEach(content.scopes) { choice in
                Toggle(isOn: Binding { choice.scope == content.scope } set: { _ in browser.setScope(choice.scope) }) {
                    Text("\(choice.title)  \(choice.count.formatted())")
                }
            }
        } label: {
            TopRowScopeLabel(title: content.scope.title, isQuiet: content.isDefaultScope)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Show")
        .accessibilityValue(content.scope.title)
        .accessibilityIdentifier("TopRowScope")
        .help("Show All Items, the Library or the Feed")
    }

    // MARK: Views

    /// The views as one fold of the row shows them. The radio group holds the views and nothing else, so the places
    /// at the row's end are outside it.
    func views(_ fold: TopRowFold) -> some View {
        HStack(spacing: 0) {
            TopRowPills(
                choices: content.views, chosen: content.chosenChoice?.id ?? "", isChanged: content.isChanged, fold: fold,
                choose: choose, newView: newView)
            Spacer(minLength: 16)
            switch fold.places {
            case .none: EmptyView()
            case .browse: browseMenu
            case .inline: inlinePlaces
            }
        }
    }

    private func choose(_ choice: TopRowContent.Choice) {
        browser.show(choice.target, in: library, order: order)
    }

    private func newView() {
        browser.openNewViewPanel(in: library)
    }

    private var browseMenu: some View {
        Menu {
            ForEach(content.places) { place in
                Button(place.count.map { "\(place.title)  \($0.formatted())" } ?? place.title) { open(place) }
            }
        } label: {
            TopRowMenuLabel(title: Text("Browse"), padding: 8)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        // The menu's own button, whose value names what it holds.
        .accessibilityLabel("Browse")
        .accessibilityValue(content.places.map(\.title).joined(separator: ", "))
        .accessibilityIdentifier("TopRowBrowse")
    }

    private var inlinePlaces: some View {
        HStack(spacing: 2) {
            ForEach(content.places) { place in
                Button { open(place) } label: {
                    HStack(spacing: 6) {
                        Text(place.title)
                        if let count = place.count { Text(count, format: .number).foregroundStyle(.tertiary) }
                    }
                }
                .buttonStyle(TopRowPillStyle(isChosen: place.target.place == content.place))
                .accessibilityAddTraits(place.target.place == content.place ? .isSelected : [])
            }
        }
        .fixedSize()
    }

    private func open(_ place: TopRowContent.Browsed) {
        browser.show(place.target, in: library, order: order)
    }
}

// MARK: Title

/// The title at one size and its count beside it on the same baseline. The count is part of the title's label for
/// VoiceOver. With the sidebar closed the title opens the sidebar's rows as a menu.
private struct TopRowTitle: View {
    @Environment(\.interfaceTextSize) private var textSize
    let title: String
    let countText: String
    let label: String
    let menu: PlacesMenu?
    let browser: Browser
    let order: ItemOrder
    @CurrentLibrary private var library

    private var scale: CGFloat { InterfaceStyle.scale(for: textSize) }
    /// The most of the row a long name takes, so the buttons and the views are never crowded out.
    private static let widest: CGFloat = 340

    private var cluster: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CappedWidth(limit: Self.widest) {
                Text(title).font(.system(size: 22 * scale, weight: .bold)).lineLimit(1).truncationMode(.tail)
            }
            Text(countText)
                .font(.system(size: 15 * scale)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                .fixedSize().layoutPriority(1)
            if menu != nil {
                Image(systemName: "chevron.down").font(.system(size: 10 * scale, weight: .semibold)).foregroundStyle(.secondary)
                    .layoutPriority(1)
            }
        }
    }

    var body: some View {
        Group {
            if let menu {
                // The menu's own button, labeled with the title and its count.
                Menu { PlacesMenuView(menu: menu, browser: browser, order: order) } label: { cluster }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(label)
                    .accessibilityHint("Opens the sidebar's places")
            } else {
                cluster
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
            }
        }
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("TopRowTitle")
    }
}

/// Lays out its one child at the width it needs up to `limit`, and narrower when the row has less. A flexible frame
/// would take the whole room offered and leave the count beside the title at the edge of it.
private struct CappedWidth: Layout {
    let limit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        return child.sizeThatFits(ProposedViewSize(width: min(proposal.width ?? limit, limit), height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        subviews.first.map { bounds.minY + $0.dimensions(in: ProposedViewSize(bounds.size))[guide] }
    }
}

// MARK: The control and the pills

private struct TopRowScopeLabel: View {
    @Environment(\.interfaceTextSize) private var textSize
    let title: String
    let isQuiet: Bool

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8 * scale, weight: .semibold))
        }
        .font(.system(size: 12 * scale, weight: .medium))
        .foregroundStyle(isQuiet ? .secondary : .primary)
        .padding(.horizontal, 8)
        .frame(height: 22 * max(1, scale))
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .contentShape(Capsule())
    }
}

private struct TopRowPillStyle: ButtonStyle {
    @Environment(\.interfaceTextSize) private var textSize
    let isChosen: Bool

    func makeBody(configuration: Configuration) -> some View {
        let scale = InterfaceStyle.scale(for: textSize)
        configuration.label
            .font(.system(size: 13 * scale, weight: isChosen ? .medium : .regular))
            .foregroundStyle(isChosen ? .primary : .secondary)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: TopRowMetrics.pillHeight * max(1, scale))
            .background { if isChosen { Capsule().fill(Color.primary.opacity(0.07)) } }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct TopRowMenuLabel: View {
    @Environment(\.interfaceTextSize) private var textSize
    let title: Text
    var padding: CGFloat = 11
    var isChosen = false

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: 4) {
            title
            Image(systemName: "chevron.down").font(.system(size: 9 * scale, weight: .semibold))
        }
        .font(.system(size: 13 * scale, weight: isChosen ? .medium : .regular))
        .foregroundStyle(isChosen ? .primary : .secondary)
        .padding(.horizontal, padding)
        .frame(height: TopRowMetrics.pillHeight * max(1, scale))
        .background { if isChosen { Capsule().fill(Color.primary.opacity(0.07)) } }
        .contentShape(Capsule())
    }
}

/// The views of a place as a radio group: each a pill, the chosen one selected, and what does not fit in a menu that ends
/// with New View…. VoiceOver reads a radio group of every view, whatever has folded.
private struct TopRowPills: View {
    let choices: [TopRowContent.Choice]
    let chosen: String
    let isChanged: Bool
    let fold: TopRowFold
    let choose: (TopRowContent.Choice) -> Void
    let newView: () -> Void

    /// None while the window shows one of the Library's places.
    private var current: TopRowContent.Choice? { choices.first { $0.id == chosen } ?? (chosen.isEmpty ? nil : choices.first) }

    private var split: (shown: [TopRowContent.Choice], hidden: [TopRowContent.Choice]) {
        guard let count = fold.shown, count < choices.count else { return (choices, []) }
        var shown = Array(choices.prefix(count))
        if let current, !shown.contains(current) { shown[shown.count - 1] = current }
        return (shown, choices.filter { !shown.contains($0) })
    }

    var body: some View {
        Group {
            if fold.onePill {
                onePill
            } else {
                let (shown, hidden) = split
                HStack(spacing: 2) {
                    ForEach(shown) { pill($0) }
                    if hidden.isEmpty { plus } else { more(hidden) }
                }
            }
        }
        .fixedSize()
        .accessibilityRepresentation {
            Group {
                Picker("Views", selection: Binding { current?.id ?? "" } set: { id in
                    if let choice = choices.first(where: { $0.id == id }) { choose(choice) }
                }) {
                    ForEach(choices) { choice in
                        Group {
                            if isChanged, choice.id == current?.id { Text("\(choice.title), changed") } else { Text(choice.title) }
                        }
                        .tag(choice.id)
                    }
                }
                .pickerStyle(.radioGroup)
                Button("New View", action: newView)
            }
        }
        .accessibilityIdentifier("TopRowViews")
    }

    private func pill(_ choice: TopRowContent.Choice) -> some View {
        let isChosen = choice.id == current?.id
        return Button { choose(choice) } label: {
            HStack(spacing: 5) {
                Text(choice.title)
                if isChosen, isChanged { Circle().fill(.secondary).frame(width: 5, height: 5).accessibilityHidden(true) }
            }
        }
        .buttonStyle(TopRowPillStyle(isChosen: isChosen))
    }

    private var plus: some View {
        Button("New View", systemImage: "plus", action: newView)
            .labelStyle(.iconOnly)
            .buttonStyle(TopRowPillStyle(isChosen: false))
            .help("New View")
    }

    private func more(_ hidden: [TopRowContent.Choice]) -> some View {
        Menu {
            ForEach(hidden) { choice in Button(choice.title) { choose(choice) } }
            Divider()
            Button("New View…", action: newView)
        } label: {
            TopRowMenuLabel(title: Text("\(hidden.count) More"))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private var onePill: some View {
        Menu {
            ForEach(choices) { choice in
                Toggle(choice.title, isOn: Binding { choice.id == current?.id } set: { _ in choose(choice) })
            }
            Divider()
            Button("New View…", action: newView)
        } label: {
            TopRowMenuLabel(title: current.map { Text($0.title) } ?? Text("Views"), isChosen: current != nil)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

enum TopRowMetrics {
    /// How far the title stands from its column's edge, as the list's first column does.
    static let lead: CGFloat = 40
    /// The same in a list column beside a page, where the title's text stands where the rows' text does.
    static let listLead: CGFloat = 16
    /// The pills start a little before the title so their words line up under it.
    static let pillsLead: CGFloat = 29
    static let pillHeight: CGFloat = 28
    /// The title's line at the least: the toolbar's usual height, which stands in full screen while the toolbar is hidden.
    static let lineHeight: CGFloat = 52
    /// How far a page's content starts above the toolbar's lower edge, under the toolbar: the kicker is 44 from the
    /// window's top in a toolbar 52 tall, and the page's own top margin is the rest.
    static let pageLift: CGFloat = 12
    /// The air below the pills in the row of views.
    static let restMargin: CGFloat = 12

    /// The row of views under the title: the pills at their size for the text size, and the air below them.
    static func restHeight(scale: CGFloat) -> CGFloat { pillHeight * max(1, scale) + restMargin }
    /// What the row keeps clear of the toolbar's buttons and of the traffic lights.
    static let clearance: CGFloat = 12
    /// How far the title stands from the last of the traffic lights, the sidebar's button and Back and Forward, as the
    /// sidebar-closed board has it.
    static let leadingClearance: CGFloat = 20
}
