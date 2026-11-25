import SwiftUI

/// The panel beside an item's page: white behind a hairline, with a pill for each part the item has (Outline, Links,
/// Info). One part has no pills. A type remembers the part last chosen (`PanelParts`), so a person can stay on Links.
/// Where the type remembers none, the part shown is chosen once when the item opens and does not change as headings
/// arrive or vanish, so a property being edited in Info is never taken from under the person.
struct ItemPanel: View {
    @AppStorage(PanelParts.key) private var remembered = PanelParts()
    @State private var opened = OpenedPart()
    let item: Item
    let outline: PanelOutlineModel
    let links: [PanelLinkGroup]
    let info: PanelInfoModel
    let onOpen: (ItemID) -> Void
    let onHeading: (Int) -> Void
    let onPage: (Int) -> Void
    let onShowHistory: () -> Void

    private var parts: [PanelPart] {
        var parts: [PanelPart] = []
        if outline.hasContent { parts.append(.outline) }
        if !links.isEmpty { parts.append(.links) }
        parts.append(.info)
        return parts
    }

    /// The part chosen when the item opened, held by the view for as long as it shows the item.
    private final class OpenedPart {
        var part: PanelPart?
    }

    /// A remembered part the item has; else the part chosen when it opened, while it is still there; else the first.
    private func shown(among parts: [PanelPart]) -> PanelPart {
        if let chosen = remembered.part(of: item.type), parts.contains(chosen) { return chosen }
        let first = opened.part ?? parts.first ?? .info
        if opened.part == nil { opened.part = first }
        return parts.contains(first) ? first : (parts.first ?? .info)
    }

    var body: some View {
        let parts = parts
        let shown = shown(among: parts)
        VStack(alignment: .leading, spacing: 0) {
            if parts.count > 1 {
                PanelPills(parts: parts, shown: shown) { PanelParts.choose($0, for: item.type) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch shown {
                    case .outline: PanelOutlineView(model: outline, onHeading: onHeading, onPage: onPage)
                    case .links: PanelLinksView(item: item.id, groups: links, onOpen: onOpen)
                    case .info: PanelInfoView(model: info, onShowHistory: onShowHistory)
                    }
                }
                .padding(.horizontal, PanelMetrics.inset)
                .padding(.top, parts.count > 1 ? PanelMetrics.contentTop : PanelMetrics.contentTopAlone)
                .padding(.bottom, PanelMetrics.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: PanelMetrics.hairline) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ItemPanel")
    }
}

/// The panel's measures in points at the default text size, which the design's `SidePanel` gives.
enum PanelMetrics {
    static let hairline: CGFloat = 0.5
    /// The room at the sides of a part, and above the pills.
    static let inset: CGFloat = 20
    static let pillsInset: CGFloat = 9
    static let pillHeight: CGFloat = 28
    static let contentTop: CGFloat = 8
    /// The room above the first line of a part that has no pills over it.
    static let contentTopAlone: CGFloat = 23
    static let rowHeight: CGFloat = 30
    static let outlineRowHeight: CGFloat = 26
    static let headingTop: CGFloat = 22
    static let headingGap: CGFloat = 8
    static let factsGap = CGSize(width: 16, height: 15)
    /// A fact's label to its value.
    static let factLabelGap: CGFloat = 5
}

/// The panel's parts as pills. They are one radio group to VoiceOver, because only one part shows at a time.
private struct PanelPills: View {
    @Environment(\.interfaceTextSize) private var textSize
    let parts: [PanelPart]
    let shown: PanelPart
    let choose: (PanelPart) -> Void

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: 2) {
            ForEach(parts, id: \.self) { part in
                Button { choose(part) } label: {
                    Text(part.title)
                        .interfaceFont(.callout.weight(part == shown ? .semibold : .regular))
                        .foregroundStyle(part == shown ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: PanelMetrics.pillHeight * scale)
                        .background(part == shown ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("PanelPill.\(part.rawValue)")
            }
        }
        .padding(.horizontal, PanelMetrics.pillsInset)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityRepresentation {
            Picker("Panel", selection: Binding(get: { shown }, set: choose)) {
                ForEach(parts, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
        }
    }
}

/// A heading in a part with its count in grey, such as Referenced By 3.
struct PanelHeading: View {
    let title: String
    var count: Int?
    var isFirst = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(verbatim: title).fontWeight(.semibold)
            if let count, count > 0 {
                Text(count, format: .number).monospacedDigit().foregroundStyle(.tertiary)
            }
        }
        .interfaceFont(.callout)
        .padding(.top, isFirst ? 4 : PanelMetrics.headingTop)
        .padding(.bottom, PanelMetrics.headingGap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A line under a part's rows that does something, such as Show All 42 Versions.
struct PanelMoreButton: View {
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .interfaceFont(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
