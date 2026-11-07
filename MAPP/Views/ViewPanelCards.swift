import SwiftUI

/// The panel's two sections for a gallery, in place of Columns: what fills each card (Cards), and what the card says
/// under its picture (Under the Card). A saved view's choices are held until Save, and a place's last as long as the
/// window (`Browser.changeCards`).
struct ViewPanelCards: View {
    let browser: Browser
    let panel: ViewPanel
    let content: ItemTableContent

    var body: some View {
        let cards = browser.cards
        ViewPanelSection(title: "Cards", note: panel.purpose == .place ? nil : "This Mac") {
            InspectorBox {
                HStack {
                    Text("Preview")
                    Spacer(minLength: 0)
                    Picker("Preview", selection: Binding { cards.preview } set: { value in browser.changeCards { $0.preview = value } }) {
                        ForEach(ViewCards.Preview.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("ViewPanelCardPreview")
                }
                Toggle("Fit Picture", isOn: Binding { cards.fitsPicture } set: { value in browser.changeCards { $0.fitsPicture = value } })
                    .disabled(!cards.preview.showsPicture)
                    .help(cards.preview.showsPicture ? "" : String(localized: "Only a card with a picture can fit it."))
                    .accessibilityIdentifier("ViewPanelCardFitPicture")
                HStack {
                    Text("Size")
                    Spacer(minLength: 0)
                    Picker("Size", selection: Binding { cards.size } set: { value in browser.changeCards { $0.size = value } }) {
                        ForEach(ViewCards.Size.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier("ViewPanelCardSize")
                }
            }
        }
        UnderTheCard(browser: browser, panel: panel, content: content)
    }
}

/// The card's Title, which always shows, its Subtext, and the properties under it: shown or hidden with the eye and
/// dragged into order.
private struct UnderTheCard: View {
    let browser: Browser
    let panel: ViewPanel
    let content: ItemTableContent
    @State private var showsHidden = false

    var body: some View {
        let cards = browser.cards
        let offered = GalleryProperty.offered(columns: content.columns, rows: content.allRows)
        let byID = Dictionary(offered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // A choice the place no longer offers keeps its place in the stored order and is not listed.
        let shown = cards.properties.compactMap { byID[$0] }
        let hidden = offered.filter { !cards.shows($0.id) }
        VStack(alignment: .leading, spacing: InspectorMetrics.headingGap) {
            HStack(spacing: 6) {
                Text("Under the Card").interfaceFont(.body.weight(.semibold))
                Spacer(minLength: 0)
                if panel.purpose != .place {
                    Text("This Mac").interfaceFont(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, InspectorMetrics.headingInset)
            .accessibilityAddTraits(.isHeader)
            InspectorBox {
                HStack(spacing: InspectorMetrics.gap) {
                    Text("Title")
                    Spacer(minLength: 0)
                    Image(systemName: "lock")
                        .foregroundStyle(.tertiary)
                        .help("The title always shows.")
                        .accessibilityLabel("Always shown")
                }
                HStack {
                    Text("Subtext")
                    Spacer(minLength: 0)
                    Picker("Subtext", selection: Binding { cards.subtext } set: { value in browser.changeCards { $0.subtext = value } }) {
                        ForEach(ViewCards.Subtext.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("ViewPanelCardSubtext")
                }
                ForEach(shown) { property in
                    CardPropertyRow(browser: browser, property: property, isShown: true)
                }
                if !hidden.isEmpty {
                    Button {
                        showsHidden.toggle()
                    } label: {
                        Label(
                            showsHidden ? "Hide \(hidden.count) Hidden" : "Show \(hidden.count) More",
                            systemImage: showsHidden ? "chevron.up" : "plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ViewPanelShowMoreProperties")
                    if showsHidden {
                        ForEach(hidden) { property in
                            CardPropertyRow(browser: browser, property: property, isShown: false)
                        }
                    }
                }
            }
        }
    }
}

private struct CardPropertyRow: View {
    @Environment(\.interfaceTextSize) private var textSize
    let browser: Browser
    let property: GalleryProperty
    let isShown: Bool

    private static let prefix = "property:"

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: InspectorMetrics.gap) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11 * scale))
                .foregroundStyle(.tertiary)
                .opacity(isShown ? 1 : 0)
                .accessibilityHidden(true)
            Text(verbatim: property.label)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isShown ? .primary : .secondary)
            Spacer(minLength: 0)
            Button {
                browser.changeCards { $0.setShown(property.id, !isShown) }
            } label: {
                Image(systemName: isShown ? "eye" : "eye.slash")
                    .foregroundStyle(isShown ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .frame(width: InspectorMetrics.trailingColumn, height: InspectorMetrics.trailingColumn)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(isShown ? "Hide Property" : "Show Property")
            .accessibilityLabel(isShown ? "Hide Property" : "Show Property")
            .accessibilityIdentifier("ViewPanelPropertyEye.\(property.id)")
        }
        .interfaceFont(.body)
        .contentShape(.rect)
        .modifier(Arrangeable(isOn: isShown, id: Self.prefix + property.id, move: move))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ViewPanelProperty.\(property.id)")
    }

    private func move(_ dragged: String) -> Bool {
        guard dragged.hasPrefix(Self.prefix) else { return false }
        let moved = String(dragged.dropFirst(Self.prefix.count))
        guard moved != property.id else { return false }
        browser.changeCards { $0.move(moved, before: property.id) }
        return true
    }
}

extension ViewCards.Preview {
    var title: String {
        switch self {
        case .pictureOrText: String(localized: "Picture or Text")
        case .picture: String(localized: "Picture")
        case .text: String(localized: "Text")
        case .none: String(localized: "None")
        }
    }
}

extension ViewCards.Size {
    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
}

extension ViewCards.Subtext {
    var title: String {
        switch self {
        case .typeAndDate: String(localized: "Type and Date")
        case .type: String(localized: "Type")
        case .date: String(localized: "Date")
        case .none: String(localized: "None")
        }
    }
}
