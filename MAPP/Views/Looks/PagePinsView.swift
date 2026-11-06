import SwiftUI

/// The pins under an item page's title, drawn in SwiftUI from `PagePins` for a page the editor does not draw: each a
/// key above its value, laid out by the header's own width as the note page's are (one row, then three to a row, then
/// two), with the same chips (`PageChip`). The pins are read only, except the status, which opens a native menu and
/// writes as the note page's does, and a linked item's chip, which opens the item. A value keeps to two lines, and a
/// list shows what `PagePins` gave it and its "+N".
struct PagePinsView: View {
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    let item: Item
    let pins: [PropertyRow]
    /// The item's status field, for a pinned status.
    let statusField: ItemTypeInfo.Field?
    let drafts: DetailsPresentation
    let open: (ItemID) -> Void

    var body: some View {
        let size = CGFloat(textSize)
        let step = size * 4 / 13
        PinLayout(step: step, size: size) {
            ForEach(pins) { pin in
                VStack(alignment: .leading, spacing: step * 1.25) {
                    Text(verbatim: pin.label)
                        .font(.system(size: size * 12 / 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minHeight: step * 3.75)
                    value(of: pin, step: step)
                }
                .layoutValue(key: PinShrink.self, value: PinShrink.weight(of: pin.value))
                .accessibilityElement(children: .contain)
            }
        }
        .font(.system(size: size))
    }

    @ViewBuilder private func value(of pin: PropertyRow, step: CGFloat) -> some View {
        ChipFlow(spacing: CGSize(width: step * 2, height: step * 1.5), rows: 2) {
            switch pin.value {
            case .status:
                if let statusField { StatusPin(item: item, field: statusField, drafts: drafts) }
            case .parent:
                EmptyView()
            case .type(let name, let icon):
                PageChip(text: name, kind: .type(icon: icon))
            case .items(let targets):
                ForEach(targets, id: \.item) { target in
                    Button { open(target.item) } label: {
                        switch target.kind {
                        case .link: PageChip(text: target.title, kind: .link(icon: target.icon))
                        case .person: PagePerson(name: target.title, initials: PersonInitials.of(target.title))
                        }
                    }
                    .buttonStyle(.plain)
                }
            case .people(let names):
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    PagePerson(name: name, initials: PersonInitials.of(name))
                }
            case .options(let words):
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    PageChip(text: word, kind: .option(OptionTone.tone(for: word)))
                }
            case .tags(let tags):
                ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                    PageChip(text: tag, kind: .tag)
                }
            case .source(let text), .date(let text), .text(let text):
                plain(text)
            case .boolean(let flag):
                plain(flag ? String(localized: "Yes") : String(localized: "No"))
            case .url(let text):
                if let url = Self.webAddress(text) { link(text, url) } else { plain(text) }
            case .email(let text):
                if let url = URL(string: "mailto:\(text)") { link(text, url) } else { plain(text) }
            case .phone(let text):
                if let url = Self.dialAddress(text) { link(text, url) } else { plain(text) }
            }
            if pin.more > 0 {
                Text(verbatim: "+\(pin.more)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .clipped()
        .frame(minHeight: step * 6)
    }

    private func plain(_ text: String) -> some View {
        Text(verbatim: text)
            .lineLimit(2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func link(_ text: String, _ url: URL) -> some View {
        Link(destination: url) {
            Text(verbatim: text)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    /// An address that opens in the browser: only a web address, as on the note page.
    static func webAddress(_ text: String) -> URL? {
        guard text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") else { return nil }
        return URL(string: text)
    }

    /// A number dialed as its digits and a leading plus, whatever spacing it is written with; nil where it has none.
    static func dialAddress(_ number: String) -> URL? {
        var dialed = ""
        for (index, character) in number.enumerated() {
            if character.isASCII, character.isNumber { dialed.append(character) } else if index == 0, character == "+" { dialed.append(character) }
        }
        guard dialed.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel:\(dialed)")
    }
}

/// The status pin: its group's mark and the status in a chip. Where the item can be changed it is a native menu of the
/// type's statuses, which writes the choice as the note page's does and says so when the library refuses; where it
/// cannot, the chip has no chevron and no menu.
private struct StatusPin: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let item: Item
    let field: ItemTypeInfo.Field
    let drafts: DetailsPresentation

    var body: some View {
        let current = PagePins.statusValue(of: item, in: field)
        let label = current.map { ItemTypeInfo.Field.label(ofOption: $0) } ?? String(localized: "Status")
        let mark = PageHeader.Mark(group: current.flatMap(field.statusGroup(of:)))
        let editable = item.isEditable && field.isPicked
        if editable {
            Menu {
                Picker("Status", selection: Binding { current ?? "" } set: { choice in
                    drafts.draft(for: item.id, key: field.key).rejected = !library.setItemProperty(
                        item.id, key: field.key, value: .string(choice), undoManager: undoManager)
                }) {
                    ForEach(ItemPageHeader.statusChoices(of: item, in: field), id: \.self) { choice in
                        Text(verbatim: ItemTypeInfo.Field.label(ofOption: choice)).tag(choice)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                PageChip(text: label, kind: .status(mark, chevron: true))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Status")
            .accessibilityValue(label)
            .accessibilityIdentifier("ItemStatusPin")
        } else {
            PageChip(text: label, kind: .status(mark, chevron: false))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Status")
                .accessibilityValue(label)
        }
    }
}

/// How much of a row's overflow a pin gives up, as flex-shrink does on the note page: the status and the type keep
/// their whole words, and a list gives way first.
private nonisolated struct PinShrink: LayoutValueKey {
    static let defaultValue: CGFloat = 1

    static func weight(of value: PropertyRow.Value) -> CGFloat {
        switch value {
        case .status, .type: 0
        case .items, .people, .options, .tags: 3
        default: 1
        }
    }
}

/// Lays the pins out by the width the header has: in one row, each as wide as it wants, while that fits at the design's
/// 440 points (at 13 points of text), then three to a row from 320, then two. The thresholds are the note page's
/// container queries, in the interface's text size.
private struct PinLayout: Layout {
    let step: CGFloat
    let size: CGFloat

    private var gap: CGSize { CGSize(width: step * 5, height: step * 4) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width } + gap.width * CGFloat(max(0, subviews.count - 1))
        return arrange(width: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, layout.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        guard !subviews.isEmpty else { return ([], .zero) }
        if width >= size * 33.85 { return row(width: width, subviews: subviews) }
        return grid(columns: width >= size * 24.6 ? 3 : 2, width: width, subviews: subviews)
    }

    private func row(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var widths = subviews.map { min($0.sizeThatFits(.unspecified).width, width / 2) }
        let overflow = widths.reduce(0, +) + gap.width * CGFloat(subviews.count - 1) - width
        if overflow > 0 {
            let weights = zip(subviews, widths).map { $0[PinShrink.self] * $1 }
            let total = weights.reduce(0, +)
            if total > 0 { widths = zip(widths, weights).map { max(0, $0 - overflow * $1 / total) } }
        }
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var height: CGFloat = 0
        for (subview, itemWidth) in zip(subviews, widths) {
            let itemHeight = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height
            frames.append(CGRect(x: x, y: 0, width: itemWidth, height: itemHeight))
            x += itemWidth + gap.width
            height = max(height, itemHeight)
        }
        return (frames, CGSize(width: width, height: height))
    }

    private func grid(columns: Int, width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let column = max(0, (width - gap.width * CGFloat(columns - 1)) / CGFloat(columns))
        var frames: [CGRect] = []
        var y: CGFloat = 0
        for start in stride(from: 0, to: subviews.count, by: columns) {
            let rowViews = subviews[start..<min(start + columns, subviews.count)]
            let heights = rowViews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }
            for (offset, height) in heights.enumerated() {
                frames.append(CGRect(x: CGFloat(offset) * (column + gap.width), y: y, width: column, height: height))
            }
            y += (heights.max() ?? 0) + gap.height
        }
        return (frames, CGSize(width: width, height: max(0, y - gap.height)))
    }
}

/// A pin's value: chips and words side by side, wrapping to at most `rows` lines. What would be a further line is
/// cut, as the note page cuts it.
private struct ChipFlow: Layout {
    let spacing: CGSize
    let rows: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, layout.frames) {
            // A cut value is placed outside the bounds, which the pin clips.
            let cut = frame.minY > layout.size.height
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + (cut ? bounds.height + 1000 : frame.minY)),
                anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var row = 0
        var widest: CGFloat = 0
        var rowStart = 0
        var visibleHeight: CGFloat = 0
        func closeRow(upTo end: Int) {
            // Centers the row's values on one line.
            for index in rowStart..<end { frames[index].origin.y = y + (rowHeight - frames[index].height) / 2 }
            if row < rows { visibleHeight = y + rowHeight }
        }
        for subview in subviews {
            let proposed = ProposedViewSize(width: width, height: nil)
            let natural = subview.sizeThatFits(proposed)
            let itemWidth = width.map { min(natural.width, $0) } ?? natural.width
            if let width, x > 0, x + itemWidth > width + 0.5 {
                closeRow(upTo: frames.count)
                y += rowHeight + spacing.height
                x = 0
                rowHeight = 0
                row += 1
                rowStart = frames.count
            }
            frames.append(CGRect(x: x, y: y, width: itemWidth, height: natural.height))
            x += itemWidth + spacing.width
            widest = max(widest, x - spacing.width)
            rowHeight = max(rowHeight, natural.height)
        }
        closeRow(upTo: frames.count)
        return (frames, CGSize(width: widest, height: visibleHeight))
    }
}
