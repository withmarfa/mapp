import SwiftUI

/// One row of the command palette: a command, a place or an item.
struct PaletteEntry: Identifiable {
    var id: String
    let title: String
    /// Feed or Archived for an item that is one, at the row's right.
    var detail: String?
    /// The words a search shows under the title where it has no excerpt: the item's text, or its type and collections.
    var snippet: String?
    /// The words around what a search found.
    var excerpt: SearchExcerpt?
    /// A search's date, at the row's right in place of the detail.
    var date: String?
    let icon: RowIcon
    var shortcut: String?
    /// Set for an item, which Actions offers more for than a command.
    var item: ItemID?
    /// Another interface takes the keyboard itself, so the page should not regain focus first.
    var takesFocus = false
    /// The menu group ⌘K lists it under with nothing typed; nil for a command only typing finds.
    var group: PaletteSections.CommandGroup? = .file
    /// Running it leaves the palette open, as a row that makes a token does.
    var staysOpen = false
    let action: () -> Void

    /// Whether the row offers a token of Search Items rather than something to open or run.
    var isOffer: Bool { id.hasPrefix(CommandPalette.offerPrefix) }
}

/// The grey of a chosen row: quiet in light and in dark, with the text keeping its own color.
private let paletteSelection = Color.primary.opacity(0.1)

/// The palette's columns, shared by the field and the rows so the typed words start where the titles do.
enum PaletteMetrics {
    /// The list's inset from the panel's edge.
    static let listInset: CGFloat = 6
    /// A row's inset inside the list.
    static let rowInset: CGFloat = 8
    /// The mark column's left edge, from the panel's edge.
    static let markInset: CGFloat = listInset + rowInset
    static let markWidth: CGFloat = 20
    static let markGap: CGFloat = 10
    /// The tallest the results grow, the filter row included; the bar adds its own height under them.
    static let resultsHeight: CGFloat = 460
}

/// The bar at the foot of the results, which rows scroll under: the filter button in Search Items, and Open and Actions.
enum PaletteBar {
    static let inset: CGFloat = 10
    static let spacing: CGFloat = 8
    /// The label size of the bar's controls, a point larger than a large control's.
    static let fontSize: CGFloat = 14
    /// The bar's height: a large glass button's, for a label a point larger than a large control's.
    static let height: CGFloat = 31
    /// How far a segment's fill, or the filter button's, sits inside its capsule.
    static let fillInset: CGFloat = 3
    static let grow = Animation.snappy(duration: 0.18)
}

struct PaletteSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .interfaceFont(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, PaletteMetrics.rowInset)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A type's mark or a command's symbol, in the one plain gray, so a row's words are what stands out.
private struct PaletteMark: View {
    let icon: RowIcon

    var body: some View {
        RowIconImage(icon: icon)
            .foregroundStyle(.secondary)
            .frame(width: PaletteMetrics.markWidth, height: PaletteMetrics.markWidth)
            .accessibilityHidden(true)
    }
}

struct PaletteRow: View {
    let entry: PaletteEntry
    let query: String
    let isHighlighted: Bool
    /// Search Items shows two lines on every row, so its rows are all one height: the title, then the words around the
    /// match or the item's own words. The command palette's rows, commands among them, all take one line.
    let isSearch: Bool
    /// Whether a search row shows the words around the match (Show Snippets); without them it takes one line.
    var showsSnippets = true
    let onHover: () -> Void
    let onRun: () -> Void

    var body: some View {
        let words = isSearch && showsSnippets ? (entry.excerpt?.attributed() ?? AttributedString(entry.snippet ?? " ")) : nil
        // A row with a second line keeps its mark and date on the title's line, as a one-line row has them.
        HStack(alignment: words == nil ? .center : .firstTextBaseline, spacing: PaletteMetrics.markGap) {
            PaletteMark(icon: entry.icon)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                titleText
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let words {
                    Text(words)
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if entry.detail != nil || (isSearch && entry.date != nil) {
                HStack(spacing: 8) {
                    ForEach([entry.detail, isSearch ? entry.date : nil].compactMap { $0 }, id: \.self) { word in
                        Text(word)
                    }
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            } else if let shortcut = entry.shortcut {
                ShortcutKeys(shortcut)
            }
        }
        .padding(.horizontal, PaletteMetrics.rowInset)
        .padding(.vertical, words == nil ? 5 : 6)
        .background(isHighlighted ? paletteSelection : .clear, in: .rect(cornerRadius: 8, style: .continuous))
        .contentShape(.rect)
        .onContinuousHover { phase in
            if case .active = phase { onHover() }
        }
        .onTapGesture(perform: onRun)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }

    /// The title with the typed words in bold.
    private var titleText: Text {
        var title = AttributedString(entry.title)
        if let range = PaletteMatch.matchRange(in: entry.title, query), let target = Range(range, in: title) {
            title[target].inlinePresentationIntent = .stronglyEmphasized
        }
        return Text(title)
    }
}

/// Open and Actions as one glass capsule of the bar's height with two segments, as the toolbar groups its buttons:
/// pointing at a segment fills only that segment.
struct PaletteFooter: View {
    let openTitle: String
    let onOpen: () -> Void
    /// The key caps beside Actions, as the person has set them; nil when Palette Actions has no shortcut.
    let actionsKeys: String?
    /// Nil where there is nothing to act on, as when nothing was found and the bar only offers New Item.
    let onActions: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Text(openTitle)
                    ShortcutKeys("↩")
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("CommandPaletteOpen")
            if let onActions {
                Button(action: onActions) {
                    HStack(spacing: 6) {
                        Text("Actions")
                        if let actionsKeys {
                            ShortcutKeys(actionsKeys)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityIdentifier("CommandPaletteActions")
            }
        }
        .buttonStyle(PaletteSegmentStyle())
        .font(.system(size: PaletteBar.fontSize))
        .padding(PaletteBar.fillInset)
        .frame(height: PaletteBar.height)
        .glassEffect(.regular, in: .capsule)
    }
}

/// A segment of the bar's capsule: a soft fill while the pointer is over it, and a deeper one while it is pressed.
private struct PaletteSegmentStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Segment(configuration: configuration)
    }

    private struct Segment: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
                .background(.primary.opacity(configuration.isPressed ? 0.16 : isHovered ? 0.1 : 0), in: .capsule)
                .contentShape(.capsule)
                .onHover { isHovered = $0 }
        }
    }
}

/// The last line of Search Items' results when what is left out of search matches too: how many more matched there, and
/// Show, which searches once more with nothing left out.
struct PaletteLeftOutLine: View {
    let text: String
    let show: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().padding(.vertical, 6)
            HStack(spacing: PaletteMetrics.markGap) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.tertiary)
                    .frame(width: PaletteMetrics.markWidth)
                Text(text)
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Button("Show", action: show)
                    .appButton(.secondary, size: .small)
                    .accessibilityLabel(Text("Show Matches Left Out of Search"))
                    .accessibilityIdentifier("CommandPaletteShowLeftOut")
            }
            .padding(.horizontal, PaletteMetrics.rowInset)
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("CommandPaletteLeftOut")
    }
}

/// What the palette says at the field's line when nothing answered the words: so, and New Item, which Return does. Where the
/// copy is still filling it says it is looking, since what matches may not have arrived.
struct PaletteNoResults: View {
    let isLooking: Bool
    let onNew: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(isLooking ? "Still Looking" : "No Results")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("CommandPaletteNoResults")
            Button(action: onNew) {
                HStack(spacing: 6) {
                    Text("New Item")
                    ShortcutKeys("↩")
                        .accessibilityHidden(true)
                }
            }
            .appButton(.secondary, size: .small)
            .accessibilityIdentifier("CommandPaletteOpen")
        }
        .accessibilityElement(children: .contain)
    }
}

/// Search Items' tokens before the field's words, as the list's search draws its own.
struct PaletteTokenRow: View {
    let tokens: PaletteTokens
    let library: any ItemLibrary
    let onRemove: (FilterClause) -> Void

    var body: some View {
        let chips = tokens.clauses.compactMap { clause in
            tokens.parts(of: clause, titles: { library.title(ofValue: $0) }).map { SearchChip(clause: clause, parts: $0) }
        }
        SearchChipRow(chips: chips, width: 360, onRemove: { onRemove($0.clause) })
    }
}

/// Where the palette's keyboard is: its own field, or the Actions panel's.
enum PaletteFocus: Hashable {
    case field, actions
}

/// What can be done to the chosen row: a panel grown out of the bar with the row's title, its actions, and a
/// field that narrows them. Escape puts the panel away and leaves the palette.
struct PaletteActionsPanel: View {
    let title: String
    let actions: [PaletteAction]
    let perform: (PaletteAction) -> Void
    /// Return in the field: reads the highlight when it is pressed, not when the view was last drawn.
    let submit: () -> Void
    let close: () -> Void
    @Binding var query: String
    @Binding var highlighted: Int
    var focus: FocusState<PaletteFocus?>.Binding

    var body: some View {
        let shown = PaletteAction.filtered(actions, by: query)
        let chosen = min(highlighted, max(shown.count - 1, 0))
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .interfaceFont(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(shown.indices, id: \.self) { index in
                    let action = shown[index]
                    if action.isDestructive, index > 0 {
                        Divider().padding(.vertical, 4)
                    }
                    row(action, isHighlighted: index == chosen)
                        .onContinuousHover { phase in
                            if case .active = phase, highlighted != index { highlighted = index }
                        }
                        .onTapGesture { perform(action) }
                }
                if shown.isEmpty {
                    Text("No Actions")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
            Divider().padding(.top, 6)
            TextField("Search for Actions", text: $query)
                .textFieldStyle(.plain)
                .focused(focus, equals: .actions)
                .appFocusRing(isFocused: focus.wrappedValue == .actions)
                .onSubmit(submit)
                .onExitCommand(perform: close)
                .padding(.horizontal, 12)
                .padding(.vertical, 13)
                .accessibilityIdentifier("CommandPaletteActionsField")
        }
        .frame(width: 300)
        .nestedPanelSurface(cornerRadius: 16)
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            focus.wrappedValue = .actions
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions")
    }

    private func row(_ action: PaletteAction, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbol)
                .frame(width: 18)
                .foregroundStyle(action.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            Text(action.title)
                .foregroundStyle(action.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                ForEach(action.keys, id: \.self) { KeyCap(key: $0) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHighlighted ? paletteSelection : .clear, in: .rect(cornerRadius: 8, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }

    /// The actions that have a shortcut of their own. While Actions is open the palette owns every one of these keys,
    /// for a row that does not offer the action too, so none reaches the window's menu.
    static let shortcutKinds: [PaletteAction.Kind] = [.openInNewWindow, .copyLink, .versionHistory, .delete]

    /// The action's own shortcut, which the key caps beside it show.
    static func shortcut(of kind: PaletteAction.Kind) -> KeyboardShortcut? {
        switch kind {
        case .openInNewWindow: KeyboardShortcut(.return, modifiers: .command)
        case .copyLink: KeyboardShortcut("c", modifiers: [.command, .shift])
        case .versionHistory: KeyboardShortcut("y", modifiers: [.command, .option])
        case .delete: KeyboardShortcut(.delete, modifiers: .command)
        default: nil
        }
    }
}
