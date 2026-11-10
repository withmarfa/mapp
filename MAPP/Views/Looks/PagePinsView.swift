import SwiftUI

/// The pins under an item page's title, drawn in SwiftUI from `PagePins` for a page the editor does not draw: each a
/// key with its row's icon above its value, in a slot of a fixed width, as the note page's are, with the same chips
/// (`PageChip`). The pins are read only, except the status, which opens a native menu and writes as the note page's
/// does, and a linked item, which opens the item. A value keeps to one line, cut with an ellipsis, with the whole of it
/// in the help, and a list shows what `PagePins` gave it and its "+N".
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
                    HStack(spacing: step) {
                        Image(systemName: pin.value.symbol)
                            .font(.system(size: size * 11 / 13))
                            .accessibilityHidden(true)
                        Text(verbatim: pin.label)
                            .font(.system(size: size * 12 / 13))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(.secondary)
                    .frame(minHeight: step * 3.75)
                    .help(pin.label)
                    value(of: pin, step: step)
                        .help(Self.wholeValue(of: pin))
                }
                .padding(.trailing, step * 2)
                .accessibilityElement(children: .contain)
            }
        }
        .font(.system(size: size))
    }

    @ViewBuilder private func value(of pin: PropertyRow, step: CGFloat) -> some View {
        HStack(spacing: step * 2) {
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
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    PageChip(text: word, kind: .option(pin.optionTones.indices.contains(index) ? pin.optionTones[index] : OptionTone.tone(for: word)))
                        .layoutPriority(index == words.count - 1 ? 0 : 1)
                }
            case .tags(let tags):
                ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                    PageChip(text: tag, kind: .tag)
                        .layoutPriority(index == tags.count - 1 ? 0 : 1)
                }
            case .empty:
                EmptyView()
            case .source(let text), .date(let text), .when(let text, _), .text(let text):
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
        .frame(maxWidth: .infinity, minHeight: step * 6, alignment: .leading)
        .clipped()
    }

    /// The words of a pin's value, for its help.
    private static func wholeValue(of pin: PropertyRow) -> String {
        switch pin.value {
        case .status, .parent, .empty: ""
        case .type(let name, _): name
        case .items(let targets): targets.map(\.title).joined(separator: ", ")
        case .people(let words), .options(let words), .tags(let words): words.joined(separator: ", ")
        case .when(_, let help): help
        case .source(let text), .date(let text), .text(let text), .url(let text), .email(let text), .phone(let text): text
        case .boolean(let flag): flag ? String(localized: "Yes") : String(localized: "No")
        }
    }

    private func plain(_ text: String) -> some View {
        Text(verbatim: text)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func link(_ text: String, _ url: URL) -> some View {
        Link(destination: url) {
            Text(verbatim: text)
                .lineLimit(1)
                .truncationMode(.tail)
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

/// Lays the pins out in slots of a fixed width, 150 points at 13 points of text, so a pin stays where it is from page to
/// page, as the note page's are: as many to a row as fit, and a pin wraps only where no slot is left.
private struct PinLayout: Layout {
    let step: CGFloat
    let size: CGFloat

    private var slot: CGFloat { size * 150 / 13 }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? slot * 4, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, layout.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        guard !subviews.isEmpty else { return ([], .zero) }
        let columns = min(4, max(1, Int(width / slot)))
        let column = min(slot, max(0, width / CGFloat(columns)))
        var frames: [CGRect] = []
        var y: CGFloat = 0
        for start in stride(from: 0, to: subviews.count, by: columns) {
            let rowViews = subviews[start..<min(start + columns, subviews.count)]
            let heights = rowViews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }
            for (offset, height) in heights.enumerated() {
                frames.append(CGRect(x: CGFloat(offset) * column, y: y, width: column, height: height))
            }
            y += (heights.max() ?? 0) + step * 4
        }
        return (frames, CGSize(width: width, height: max(0, y - step * 4)))
    }
}
