import SwiftUI

/// What an index page can be set to: how it shows its rows and how wide it runs. The toolbar's View Options menu and
/// the View menu offer the same choices; only the View menu binds keys.
struct IndexViewOptions: View {
    let place: IndexPlace
    var bindsKeys = false
    @AppStorage private var layout: IndexLayout
    @AppStorage private var width: IndexWidth

    init(place: IndexPlace, bindsKeys: Bool = false) {
        self.place = place
        self.bindsKeys = bindsKeys
        _layout = AppStorage(wrappedValue: .default, place.layoutKey)
        _width = AppStorage(wrappedValue: .default, place.widthKey)
    }

    var body: some View {
        Group {
            Section("Show As") {
                ForEach(Array(IndexLayout.allCases.enumerated()), id: \.element) { offset, choice in
                    Toggle(choice.title, systemImage: choice.symbol, isOn: Binding { layout == choice } set: { _ in layout = choice })
                        .keyboardShortcut(bindsKeys ? KeyboardShortcut(KeyEquivalent(Character("\(offset + 1)")), modifiers: .command) : nil)
                        .accessibilityIdentifier("IndexShowAs\(choice.rawValue.capitalized)")
                }
            }
            Section("Width") {
                ForEach(IndexWidth.allCases) { choice in
                    Toggle(choice.title, isOn: Binding { width == choice } set: { _ in width = choice })
                        .accessibilityIdentifier("IndexWidth\(choice.rawValue.capitalized)")
                }
            }
        }
    }
}

extension IndexLayout {
    var title: LocalizedStringKey {
        switch self {
        case .list: "List"
        case .cards: "Cards"
        case .table: "Table"
        }
    }
}

extension IndexWidth {
    var title: LocalizedStringKey {
        switch self {
        case .narrow: "Narrow"
        case .standard: "Standard"
        case .wide: "Wide"
        }
    }
}

/// The toolbar's one menu of an index page's options, where the other pages keep View Options.
struct IndexViewOptionsMenu: View {
    let place: IndexPlace

    var body: some View {
        Menu("View Options", systemImage: "slider.horizontal.3") {
            IndexViewOptions(place: place)
        }
        .menuIndicator(.hidden)
        .help("View Options")
        .accessibilityIdentifier("ViewOptionsToolbar")
    }
}

extension ViewOptionCommand {
    /// The index page's choices not already made, for the command palette.
    static func indexCommands(for place: IndexPlace) -> [ViewOptionCommand] {
        let layout = IndexPreferences.layout(for: place)
        let width = IndexPreferences.width(for: place)
        let layouts = IndexLayout.allCases.filter { $0 != layout }.map { choice in
            ViewOptionCommand(title: choice.commandTitle, systemImage: choice.symbol) { IndexPreferences.set(choice, for: place) }
        }
        let widths = IndexWidth.allCases.filter { $0 != width }.map { choice in
            ViewOptionCommand(title: choice.commandTitle, systemImage: "arrow.left.and.right") {
                IndexPreferences.set(choice, for: place)
            }
        }
        return layouts + widths
    }
}

private extension IndexLayout {
    var commandTitle: String {
        switch self {
        case .list: String(localized: "View as List")
        case .cards: String(localized: "View as Cards")
        case .table: String(localized: "View as Table")
        }
    }
}

private extension IndexWidth {
    var commandTitle: String {
        switch self {
        case .narrow: String(localized: "Width: Narrow")
        case .standard: String(localized: "Width: Standard")
        case .wide: String(localized: "Width: Wide")
        }
    }
}
