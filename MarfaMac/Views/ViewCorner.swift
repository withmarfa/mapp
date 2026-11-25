import SwiftUI

/// The corner each layout of a collection has: the calendar's, the timeline's Today and the gallery's card size. Any
/// other layout has nothing to set, so draws nothing; the map draws its own zoom controls.
struct ViewCorner: View {
    @Bindable var browser: Browser
    let width: CGFloat

    var body: some View {
        switch browser.viewMode {
        case .calendar:
            CalendarCornerView(browser: browser, width: width)
        case .timeline:
            WindowCorner {
                Button("Today") { browser.requestTimelineToday() }
                    .buttonStyle(CornerButtonStyle())
                    .accessibilityLabel("Today")
                    .accessibilityIdentifier("TimelineToday")
            }
        case .gallery:
            WindowCorner {
                CornerMenu(title: browser.cards.size.title) {
                    GalleryCardSizeOptions(browser: browser)
                }
                .help("Card Size")
                .accessibilityIdentifier("GalleryCardSize")
            }
        case .list, .table, .board, .digest, .map:
            EmptyView()
        }
    }
}

/// The gallery's card size as a choice of three, ticked for the one showing. It is the value the View panel's Card Size
/// reads and writes.
struct GalleryCardSizeOptions: View {
    @Bindable var browser: Browser

    var body: some View {
        Picker("Card Size", selection: Binding { browser.cards.size } set: { browser.setCardSize($0) }) {
            ForEach(ViewCards.Size.allCases, id: \.self) { Text($0.cardsTitle).tag($0) }
        }
        .pickerStyle(.inline)
    }
}

extension ViewCards.Size {
    /// The menu's wording, where the choice sits beside other kinds of item.
    var cardsTitle: LocalizedStringResource {
        switch self {
        case .small: "Small Cards"
        case .medium: "Medium Cards"
        case .large: "Large Cards"
        }
    }
}

private struct ViewCornerModifier: ViewModifier {
    @Bindable var browser: Browser
    /// Wide until measured, so the corner is never drawn folded for a frame.
    @State private var width: CGFloat = .infinity
    @Environment(\.interfaceTextSize) private var textSize

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, browser.viewMode.hasCorner ? CornerMetrics.clearance(scale: InterfaceStyle.scale(for: textSize)) : 0, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay { ViewCorner(browser: browser, width: width) }
    }
}

extension View {
    /// Puts the corner of the collection's layout over this content column, ending where the right sidebar begins.
    func viewCorner(_ browser: Browser) -> some View { modifier(ViewCornerModifier(browser: browser)) }
}
