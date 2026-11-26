import AppKit
import SwiftUI

/// An item's head drawn in SwiftUI from `PageHead`, for a page the editor does not draw, as the editor's page draws it:
/// the kicker, then `title`, then the pins while they are on, then the rows with Show More, over a hairline. Values are
/// shown and links open; the status opens a native menu and writes as the item page's does. A value keeps to one line
/// but a long text, which keeps to two, with the whole of it in the help.
struct PageHeadView<Title: View>: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    let item: Item
    let head: PageHead
    /// The item's status field, for its status.
    let statusField: ItemTypeInfo.Field?
    let drafts: DetailsPresentation
    let open: (ItemID) -> Void
    /// Opens the editor of a row the item can take an edit for, under the view given. Nil leaves every value read only.
    var edit: ((PropertyRow, NSView) -> Void)?
    @ViewBuilder let title: Title
    @State private var expanded = false

    var body: some View {
        let size = CGFloat(InterfaceStyle.defaultTextSize) * InterfaceStyle.scale(for: textSize)
        let step = size * 4 / 13
        let shown = expanded ? head.rows : head.rows.filter { !$0.folded }
        VStack(alignment: .leading, spacing: 0) {
            PageKicker(kicker: head.kicker) {
                drafts.typeChange = TypeChangeRequest(ids: [item.id], undoManager: undoManager)
            }
                .padding(.bottom, size * 6 / 13)
            title
            if !head.pins.isEmpty {
                PinLayout(step: step, size: size) {
                    ForEach(head.pins) { pin in
                        VStack(alignment: .leading, spacing: step * 1.25) {
                            HStack(spacing: step) {
                                Image(systemName: pin.symbolName)
                                    .font(.system(size: Typography.caption * InterfaceStyle.scale(for: textSize)))
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
                                .help(pin.wholeValue)
                        }
                        .padding(.trailing, step * 2)
                        .accessibilityElement(children: .contain)
                    }
                }
                .padding(.top, step * 4)
            }
            if !shown.isEmpty || head.foldedCount > 0 {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            HStack(spacing: step * 2) {
                                Image(systemName: row.symbolName)
                                    .frame(width: size * 16 / 13)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                                Text(verbatim: row.label)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: size * 150 / 13, alignment: .leading)
                            EditableValue(row: row, edit: edit) {
                                value(of: row, step: step)
                                    .help(row.wholeValue)
                            }
                        }
                        .frame(minHeight: size * 32 / 13)
                        .opacity(row.muted ? 0.45 : 1)
                        .accessibilityElement(children: .contain)
                    }
                    if head.foldedCount > 0 {
                        Button(expanded ? String(localized: "Show Less") : head.showMore) { expanded.toggle() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .frame(minHeight: size * 30 / 13)
                    }
                }
                .padding(.top, step * (head.pins.isEmpty ? 4 : 4.5))
                .padding(.bottom, step * 2)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
        .font(.system(size: size))
        .onChange(of: item.id) { expanded = false }
    }

    @ViewBuilder private func value(of row: PropertyRow, step: CGFloat) -> some View {
        HStack(spacing: step * 1.5) {
            switch row.value {
            case .status:
                if let statusField { StatusPin(item: item, field: statusField, drafts: drafts) }
            case .parent:
                if let target = library.relationships(for: item.id).first(where: { $0.field == PagePlacement.parent })?.targets.first,
                   let id = target.itemID {
                    Button { open(id) } label: {
                        MarkedName(text: target.title, icon: PageHead.typeIcon(of: id, in: library), underlinesOnHover: true)
                    }
                    .buttonStyle(.plain)
                }
            case .items(let targets):
                ForEach(targets, id: \.item) { target in
                    Button { open(target.item) } label: {
                        switch target.kind {
                        case .link: MarkedName(text: target.title, icon: target.icon, underlinesOnHover: true)
                        case .person: PagePerson(name: target.title, initials: PersonInitials.of(target.title))
                        }
                    }
                    .buttonStyle(.plain)
                }
            case .people(let names):
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 6) {
                        PagePerson(name: name, initials: PersonInitials.of(name))
                        if row.answers.indices.contains(index), !row.answers[index].isEmpty {
                            Text(row.answers[index]).foregroundStyle(.tertiary)
                        }
                    }
                }
            case .options(let words):
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    PageChip(text: word, kind: .option(row.optionTones.indices.contains(index) ? row.optionTones[index] : OptionTone.tone(for: word)))
                        .layoutPriority(index == words.count - 1 ? 0 : 1)
                }
            case .tags(let tags):
                ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                    PageChip(text: tag, kind: .tag)
                        .layoutPriority(index == tags.count - 1 ? 0 : 1)
                }
            case .empty:
                Text("Empty").foregroundStyle(.tertiary)
            case .when(let time, let note):
                plain(time)
                Text(verbatim: note).foregroundStyle(.tertiary).lineLimit(1)
            case .text(let text):
                Text(verbatim: text)
                    .lineLimit(row.long ? 2 : 1)
                    .truncationMode(.tail)
            case .date(let text):
                plain(text)
            case .boolean(let flag):
                plain(flag ? String(localized: "Yes") : String(localized: "No"))
            case .url(let text):
                if let url = BrowserTarget.webAddress(text) { link(text, url) } else { plain(text) }
            case .email(let text):
                if let url = URL(string: "mailto:\(text)") { link(text, url) } else { plain(text) }
            case .phone(let text):
                if let url = PageHead.dialAddress(text) { link(text, url) } else { plain(text) }
            }
            if row.more > 0 {
                Text(verbatim: PageHead.moreText(row.more))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, minHeight: step * 5, alignment: .leading)
        .clipped()
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

}

/// The status pin: its group's mark and the status in a chip. Where the item can be changed it is a native menu of the
/// type's statuses, which writes the choice as the item page's does and says so when the library refuses; where it
/// cannot, it is the chip alone.
private struct StatusPin: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    let item: Item
    let field: ItemTypeInfo.Field
    let drafts: DetailsPresentation

    var body: some View {
        let current = PageHead.statusValue(of: item, in: field)
        let label = current.map { ItemTypeInfo.Field.label(ofOption: $0) } ?? String(localized: "Status")
        let mark = StatusSymbol(group: current.flatMap(field.statusGroup(of:)))
        let editable = item.allows(.fields) && field.isPicked
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
                PageChip(text: label, kind: .status(mark))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Status")
            .accessibilityValue(label)
            .accessibilityIdentifier("ItemStatusPin")
        } else {
            PageChip(text: label, kind: .status(mark))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Status")
                .accessibilityValue(label)
        }
    }
}

/// Lays the pins out in slots of a fixed width, 150 points at 13 points of text, so a pin stays where it is from page to
/// page, as the item page's are: as many to a row as fit, and a pin wraps only where no slot is left.
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

/// The kicker of a head SwiftUI draws: the type's mark in its tone and its name, 12 points at 500 in grey, then each of
/// Read Only, Feed and Archived with its symbol, lighter. VoiceOver reads it as one heading. Where the type can be
/// changed (`changesType`), its name is a button that asks for Change Type.
struct PageKicker: View {
    @AppStorage(InterfaceKey.textSize) private var textSize = InterfaceStyle.defaultTextSize
    let kicker: PageHead.Kicker
    let changeType: () -> Void

    var body: some View {
        let size = CGFloat(InterfaceStyle.defaultTextSize) * InterfaceStyle.scale(for: textSize)
        HStack(spacing: size * 8 / 13) {
            if kicker.changesType {
                Button(action: changeType) { typeName(size) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: "\(kicker.typeName), \(String(localized: "Change Type"))"))
            } else {
                typeName(size)
            }
            ForEach(kicker.flags, id: \.self) { flag in
                HStack(spacing: size * 4 / 13) {
                    Image(systemName: flag.symbol)
                    Text(verbatim: flag.words)
                }
                .fontWeight(.regular)
                .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: Typography.chip * InterfaceStyle.scale(for: textSize), weight: .medium))
        .frame(minHeight: size * 20 / 13)
        // Where the type name is a button, the heading holds it and the flags, so the button stays reachable.
        .accessibilityElement(children: kicker.changesType ? .contain : .ignore)
        .accessibilityLabel(kicker.changesType ? "" : kicker.spoken)
        .accessibilityAddTraits(.isHeader)
    }

    private func typeName(_ size: CGFloat) -> some View {
        HStack(spacing: size * 6 / 13) {
            TonedGlyph(id: kicker.typeIcon, size: size * 12 / 13)
            Text(verbatim: kicker.typeName)
        }
        .foregroundStyle(.secondary)
    }
}

/// A row's value, which a click on it opens in its editor where the row can take one. The status keeps its own menu, and a
/// chip that links keeps its link.
private struct EditableValue<Content: View>: View {
    let row: PropertyRow
    let edit: ((PropertyRow, NSView) -> Void)?
    @ViewBuilder let content: Content
    @State private var anchor = ValueEditAnchorBox()

    var body: some View {
        if let edit, row.editable, row.value != .status {
            content
                .background(ValueEditAnchor(box: anchor))
                .contentShape(.rect)
                .onTapGesture { if let view = anchor.view { edit(row, view) } }
        } else {
            content
        }
    }
}
