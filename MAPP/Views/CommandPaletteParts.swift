import SwiftUI

/// One row of the command palette: a command, a place or an item.
struct PaletteEntry: Identifiable {
    var id: String
    let title: String
    /// The type's name for an item, at the row's right.
    var detail: String?
    /// The words a search shows under the title where it has no excerpt.
    var snippet: String?
    /// The words around what a search found.
    var excerpt: SearchExcerpt?
    /// A search's date, at the row's right in place of the detail.
    var date: String?
    let icon: RowIcon
    var shortcut: String?
    /// Set for an item, which Actions offers more for than a command.
    var item: ItemID?
    /// Another interface takes the keyboard itself, so the note should not regain focus first.
    var takesFocus = false
    let action: () -> Void
}

/// The grey of a chosen row: quiet in light and in dark, with the text keeping its own color.
private let paletteSelection = Color.primary.opacity(0.1)

struct PaletteSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .interfaceFont(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A type's mark in its tone, or a command's symbol.
private struct PaletteMark: View {
    let icon: RowIcon
    var isLarge = false

    var body: some View {
        Group {
            switch icon {
            case .type(let name):
                TypeMark(icon: name, size: isLarge ? .large : .side)
            case .symbol:
                RowIconImage(icon: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
        }
        .frame(width: isLarge ? 32 : 20)
        .accessibilityHidden(true)
    }
}

struct PaletteRow: View {
    let entry: PaletteEntry
    let query: String
    let isHighlighted: Bool
    /// Search Notes shows two lines: the title, then the words around the match.
    let isSearch: Bool
    let onHover: () -> Void
    let onRun: () -> Void

    var body: some View {
        let words = isSearch ? (entry.excerpt?.attributed() ?? entry.snippet.map { AttributedString($0) }) : nil
        HStack(spacing: 10) {
            PaletteMark(icon: entry.icon, isLarge: words != nil)
            VStack(alignment: .leading, spacing: 1) {
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
            if let trailing = isSearch ? entry.date : entry.detail ?? entry.shortcut {
                Text(trailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, words == nil ? 5 : 4)
        .background(isHighlighted ? paletteSelection : .clear, in: .rect(cornerRadius: 8, style: .continuous))
        .contentShape(.rect)
        .help(entry.title)
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

/// A key of a shortcut, drawn as a small cap.
struct KeyCap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(minWidth: 16, minHeight: 16)
            .background(.quaternary, in: .rect(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Open and Actions, a small glass capsule over the bottom right of the results.
struct PaletteFooter: View {
    let openTitle: String
    let onOpen: () -> Void
    let onActions: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Text(openTitle)
                    KeyCap(key: "↩")
                }
            }
            .accessibilityIdentifier("CommandPaletteOpen")
            Button(action: onActions) {
                HStack(spacing: 4) {
                    Text("Actions")
                    KeyCap(key: "⌘")
                    KeyCap(key: "K")
                }
            }
            .accessibilityIdentifier("CommandPaletteActions")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }
}

/// The round glass button at the bottom left that shows and hides the filter row, with the number of filters set
/// beside its symbol.
struct PaletteFilterButton: View {
    let count: Int
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            if count > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text(count, format: .number)
                }
            } else {
                Image(systemName: "line.3.horizontal.decrease")
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(count > 0 ? .capsule : .circle)
        .controlSize(.large)
        .tint(count > 0 || isOn ? .accentColor : nil)
        .help(isOn ? "Hide Filters" : "Show Filters")
        .accessibilityLabel(isOn ? "Hide Filters" : "Show Filters")
        .accessibilityIdentifier("CommandPaletteFilters")
    }
}

/// The row under the field that holds the filters' chips. It holds only the add button until the chips are built
/// for it: they go inside this row, ahead of the button.
struct PaletteFilterRow: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .accessibilityIdentifier("CommandPaletteFilterRow")
    }
}

/// Where the palette's keyboard is: its own field, or the Actions panel's.
enum PaletteFocus: Hashable {
    case field, actions
}

/// What can be done to the chosen row: a panel over the buttons with the row's title, its actions, and a field that
/// narrows them. Escape puts the panel away and leaves the palette.
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
            TextField("Search for Actions…", text: $query)
                .textFieldStyle(.plain)
                .focused(focus, equals: .actions)
                .onSubmit(submit)
                .onExitCommand(perform: close)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .accessibilityIdentifier("CommandPaletteActionsField")
        }
        .frame(width: 300)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
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
