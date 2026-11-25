import SwiftUI

/// The pieces every page of the View panel is drawn from: its head, its sections under a hairline, its rows and the grey
/// line at its foot. A row is at least 32 points high: a symbol, a label, its value in grey, then its end.
enum ViewPanelMetrics {
    static let width: CGFloat = 356
    static let rowHeight: CGFloat = 32
    static let inset: CGFloat = 16
    static let symbolWidth: CGFloat = 18
    /// The most the panel grows to before its body scrolls.
    static let maxHeight: CGFloat = 640
}

/// The head of a page: the view's name and More on the first page, a back arrow and the part's name one level in.
struct ViewPanelHead<Trailing: View>: View {
    let title: String
    var back: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            if let back {
                Button("Back", systemImage: "chevron.backward", action: back)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ViewPanelBack")
            }
            Text(verbatim: title)
                .interfaceFont(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: ViewPanelMetrics.rowHeight)
        .padding(.leading, ViewPanelMetrics.inset)
        .padding(.trailing, 14)
        .padding(.top, 6)
    }
}

extension ViewPanelHead where Trailing == EmptyView {
    init(title: String, back: (() -> Void)? = nil) {
        self.init(title: title, back: back) { EmptyView() }
    }
}

/// One section of a page, under a hairline, with its heading where it has one.
struct ViewPanelSection<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, ViewPanelMetrics.inset)
                .padding(.vertical, 4)
            if let title {
                Text(verbatim: title)
                    .interfaceFont(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ViewPanelMetrics.inset)
                    .padding(.vertical, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
    }
}

/// How a row ends: a right arrow for a row that opens a part, two arrows for one of a few choices, a switch, or nothing.
enum ViewPanelRowEnd {
    case opens, pops, none
}

/// A row's look: its symbol, label, grey value and end. The row that holds it decides what a click does.
struct ViewPanelRowLabel: View {
    let symbol: String
    let label: String
    var value: String?
    var end = ViewPanelRowEnd.none

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: ViewPanelMetrics.symbolWidth)
                .accessibilityHidden(true)
            Text(verbatim: label)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if let value {
                Text(verbatim: value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            switch end {
            case .opens:
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            case .pops:
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            case .none:
                EmptyView()
            }
        }
        .interfaceFont(.body)
        .frame(minHeight: ViewPanelMetrics.rowHeight)
        .padding(.horizontal, ViewPanelMetrics.inset)
        .contentShape(.rect)
    }
}

/// A row that opens a part of the panel in place.
struct ViewPanelOpenRow: View {
    let symbol: String
    let label: String
    var value: String?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            ViewPanelRowLabel(symbol: symbol, label: label, value: value, end: .opens)
        }
        .buttonStyle(.plain)
        .accessibilityValue(value.map { Text(verbatim: $0) } ?? Text(""))
    }
}

/// A row whose value is one of a few choices, which a menu with a tick at the chosen one changes.
struct ViewPanelChoiceRow<Choice: Hashable>: View {
    let symbol: String
    let label: String
    let choices: [Choice]
    let title: (Choice) -> String
    let selection: Choice
    let choose: (Choice) -> Void

    var body: some View {
        Menu {
            ForEach(choices, id: \.self) { choice in
                Toggle(isOn: Binding { selection == choice } set: { _ in choose(choice) }) {
                    Text(verbatim: title(choice))
                }
            }
        } label: {
            ViewPanelRowLabel(symbol: symbol, label: label, value: title(selection), end: .pops)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: title(selection)))
    }
}

/// A row that ends in a switch.
struct ViewPanelSwitchRow: View {
    let symbol: String
    let label: String
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: ViewPanelMetrics.symbolWidth)
                .accessibilityHidden(true)
            Toggle(isOn: Binding { isOn } set: { set($0) }) {
                Text(verbatim: label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .interfaceFont(.body)
        .frame(minHeight: ViewPanelMetrics.rowHeight)
        .padding(.horizontal, ViewPanelMetrics.inset)
    }
}

/// A quiet button at the end of a list, such as Add Sort.
struct ViewPanelAddRow: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ViewPanelRowLabel(symbol: "plus", label: label)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

/// The grey line at a page's foot, which says where its choices are kept.
struct ViewPanelFoot: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, ViewPanelMetrics.inset)
                .padding(.vertical, 4)
            Text(verbatim: text)
                .interfaceFont(.subheadline)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, ViewPanelMetrics.inset)
                .padding(.bottom, 10)
                .padding(.top, 2)
        }
    }
}

/// The six-dot grip that leads each row of an ordered list.
struct ViewPanelGrabber: View {
    var isHidden = false

    var body: some View {
        Image(systemName: "circle.grid.2x3.fill")
            .font(.system(size: 8))
            .foregroundStyle(.tertiary)
            .opacity(isHidden ? 0 : 1)
            .frame(width: 12)
            .accessibilityHidden(true)
    }
}

/// Drag to reorder, and the keyboard's way to the same move.
struct Arrangeable: ViewModifier {
    let isOn: Bool
    let id: String
    let move: (String) -> Bool

    func body(content: Content) -> some View {
        if isOn {
            content
                .draggable(LayoutRowDrag(id: id))
                .dropDestination(for: LayoutRowDrag.self) { (drops: [LayoutRowDrag], _: CGPoint) -> Bool in
                    drops.first.map { move($0.id) } ?? false
                }
        } else {
            content
        }
    }
}

/// Where each part's choices are kept, as its foot says.
enum ViewPanelKeeping {
    static let marfa = String(localized: "Saved in Marfa for every app.")
    static let mac = String(localized: "Kept for Marfa for Mac.")
    static let savedViewOverview = String(localized: "Everything under Items is saved in Marfa for every app. The rest is kept for Marfa for Mac.")

    /// The foot of a part whose choices Marfa saves in a saved view, and this Mac keeps for a place.
    static func foot(of panel: ViewPanel) -> String {
        panel.purpose == .place ? mac : marfa
    }
}
