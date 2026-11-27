import AppKit
import MarfaIcons
import SwiftUI

/// What the page's head shows, for the web page to draw above the item so the two scroll as one surface: the item's
/// title, or the person's unsaved draft of it, and its `PageHead` (the kicker, the pins and the rows). What it does stays
/// native.
nonisolated struct PageHeader: Encodable, Equatable, Sendable {
    /// The status or the parent as the menu the page opens from it, wherever the page draws it. The page draws the
    /// button; the app builds the menu. A parent exists only with a value.
    struct Pin: Encodable, Equatable, Sendable {
        /// A status's symbol, as the page names it among the images the app sends (`PageHeaderIcons.symbols`), and the
        /// tint it takes from the page's colors. The catalogue holds neither: they follow the group the type puts the
        /// status in (`StatusSymbol`).
        struct Mark: Encodable, Hashable, Sendable {
            var symbol: String
            var tint: StatusSymbol.Tint

            init(_ status: StatusSymbol) {
                symbol = status.systemName
                tint = status.tint
            }
        }

        var label: String
        var enabled: Bool
        /// Only the status pin has a mark.
        var mark: Mark?
        /// Only the parent pin has these: the parent's type icon and the tone of its chip, as a linked item's has.
        var icon: TypeIconRef?
        var tone: String?
        /// Only the parent pin has it: the parent's item, so a pause on the pill shows the parent's card.
        var item: String?
    }

    /// The kicker as the page draws it: the type's mark in its tone and its name, then each flag with its symbol.
    struct Kicker: Encodable, Equatable, Sendable {
        struct Flag: Encodable, Equatable, Sendable {
            var id: String
            var words: String
            /// The flag's symbol among the images the app sends.
            var symbol: String
        }

        var type: String
        var icon: TypeIconRef
        var tone: String
        /// Whether the type's name asks for Change Type (`changeType`).
        var changesType: Bool
        var flags: [Flag]
        /// What VoiceOver reads for the whole line.
        var spoken: String

        init(_ kicker: PageHead.Kicker) {
            type = kicker.typeName
            icon = TypeIconRef(name: kicker.typeIcon)
            tone = TypeTone(icon: kicker.typeIcon).rawValue
            changesType = kicker.changesType
            flags = kicker.flags.map { Flag(id: $0.rawValue, words: $0.words, symbol: $0.symbol) }
            spoken = kicker.spoken
        }
    }

    /// Every chip look as CSS custom properties for the page, resolved for light and for dark so an appearance
    /// change needs no resend: the sizes and fills (`ChipLooks.cssVariables`) and each tone's color as
    /// `--tone-<name>`. A chip names its tone and the page forwards the name.
    struct ChipStyle: Encodable, Equatable, Sendable {
        var light: [String: String]
        var dark: [String: String]

        @MainActor
        init(looks: ChipLooks = .current) {
            func variables(dark: Bool) -> [String: String] {
                var all = ChipLooks.cssVariables(dark: dark, looks: looks)
                for tone in TypeTone.allCases { all["--tone-\(tone.rawValue)"] = tone.cssColor(dark: dark) }
                return all
            }
            light = variables(dark: false)
            dark = variables(dark: true)
        }
    }

    /// A type's icon as the page names it among the images the app sends (`TypeIconKey`), and the Iconify ID the app
    /// draws it from.
    struct TypeIconRef: Encodable, Equatable, Sendable {
        var name: String?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(TypeIconKey.value(for: name))
        }
    }

    /// A place's map as a still picture for each appearance, nil while it is being made, with what VoiceOver reads for it.
    struct Map: Encodable, Equatable, Sendable {
        var light: String?
        var dark: String?
        var label: String
        /// Apple Maps' attribution and its legal link, which a snapshot carries none of: the page draws both on the picture,
        /// whatever its width.
        var attribution: String
        var legal: String
        var legalAddress: String
    }

    var item: String
    /// The page is in Focus: the head is hidden, and the footer stays as it is.
    var focused = false
    var title: String
    var draft: String?
    var titleRejected: Bool
    /// Why a title is refused, which depends on the library.
    var titleRefusal: String
    var editable: Bool
    /// False where the item is titled by the first line of its text, which the page already shows as its text.
    var showsTitle = true
    /// The item's text is drawn large in the title's place and its rows follow it, as a highlight's passage is. The text
    /// is the same text, edited as text, so only its look and its place against the rows change.
    var textLeads = false
    var kicker: Kicker
    /// The status menu, for the status row or pin, which holds it; nil where the item holds no status.
    var status: Pin?
    /// The parent menu, for the parent row; nil where the item has no parent.
    var parent: Pin?
    /// The pinned properties under the title, in the order the person chose, while pinned properties are on.
    var pins: [PropertyRow]
    /// Every row, in order; the page shows those not `folded` until Show More is opened.
    var rows: [PropertyRow]
    /// "Show N More".
    var showMore: String
    /// What is listed under the text: the item's sub-items, and the items that link to it.
    var foot: PageFoot
    /// A place's map, drawn between its rows and its foot; nil for an item with no point to show.
    var map: Map?
    /// Whether the page has text to write. A collection with no text shows nothing to type into.
    var showsText: Bool
    var interfaceTextSize: Int
    /// How many lines the title shows before an ellipsis cuts it, while it is not being edited.
    var titleLines: Int
    var chips: ChipStyle

    /// The icons of the types the head names, which the page draws as images.
    var typeIconNames: Set<String?> {
        var names: Set<String?> = [kicker.icon.name]
        names.formUnion(foot.icons)
        if let parent = parent?.icon { names.insert(parent.name) }
        for value in (pins + rows).map(\.value) {
            if case .items(let targets) = value { names.formUnion(targets.map(\.icon)) }
        }
        return names
    }
}

extension PropertyRow: Encodable {
    private enum Key: String, CodingKey { case id, label, symbol, kind, text, note, texts, items, options, people, more, itemsAfter, moreItems, help, editable, long, folded, muted, section }
    /// What the page draws of an item a row links to: a type chip in the item's own tone, or a person's initials and
    /// name. The tone is one of `TypeTone`'s names; the page never picks a color.
    private struct Link: Encodable {
        let title: String
        let item: String
        let symbol: String
        let kind: String
        let tone: String?
        let initials: String?

        init(_ target: Target) {
            title = target.title
            item = target.item.rawValue
            symbol = TypeIconKey.value(for: target.icon)
            kind = target.kind.rawValue
            tone = target.kind == .link ? TypeTone(icon: target.icon).rawValue : nil
            initials = target.kind == .person ? PersonInitials.of(target.title) : nil
        }
    }
    /// A person a list names: initials and a name, with no item to open.
    private struct Listed: Encodable {
        let title: String
        let initials: String?
        /// What the person answers, in grey after the name.
        let note: String?
    }
    private struct Option: Encodable {
        let label: String
        let tone: String
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(symbolName, forKey: .symbol)
        switch value {
        case .status: try container.encode("status", forKey: .kind)
        case .empty: try container.encode("empty", forKey: .kind)
        case .parent: try container.encode("parent", forKey: .kind)
        case .items(let targets):
            try container.encode("items", forKey: .kind)
            try container.encode(targets.map(Link.init), forKey: .items)
            if targets.count > PageHead.rowLinkLimit {
                try container.encode(PageHead.rowLinkLimit, forKey: .itemsAfter)
                try container.encode(PageHead.moreLinksText(targets.count - PageHead.rowLinkLimit), forKey: .moreItems)
            }
        case .people(let names):
            try container.encode("people", forKey: .kind)
            try container.encode(names.enumerated().map { index, name in
                Listed(title: name, initials: PersonInitials.of(name), note: answers.indices.contains(index) && !answers[index].isEmpty ? answers[index] : nil)
            }, forKey: .people)
        case .options(let options):
            try container.encode("options", forKey: .kind)
            try container.encode(
                options.enumerated().map { Option(label: $1, tone: (optionTones.indices.contains($0) ? optionTones[$0] : OptionTone.tone(for: $1)).rawValue) },
                forKey: .options)
        case .tags(let tags):
            try container.encode("tags", forKey: .kind)
            try container.encode(tags, forKey: .texts)
        case .date(let text): try Self.encode("date", text, into: &container)
        case .when(let text, let note):
            try Self.encode("when", text, into: &container)
            try container.encode(note, forKey: .note)
        case .url(let text): try Self.encode("url", text, into: &container)
        case .email(let text): try Self.encode("email", text, into: &container)
        case .phone(let text): try Self.encode("phone", text, into: &container)
        case .boolean(let flag):
            try Self.encode("text", flag ? String(localized: "Yes") : String(localized: "No"), into: &container)
        case .text(let text): try Self.encode("text", text, into: &container)
        }
        if more > 0 { try container.encode(PageHead.moreText(more), forKey: .more) }
        // A link that takes no change says why where the whole value would be the help.
        if let help = lock ?? help { try container.encode(help, forKey: .help) }
        if editable { try container.encode(true, forKey: .editable) }
        if long { try container.encode(true, forKey: .long) }
        if folded { try container.encode(true, forKey: .folded) }
        if muted { try container.encode(true, forKey: .muted) }
        if let section { try container.encode(section, forKey: .section) }
    }

    private static func encode(_ kind: String, _ text: String, into container: inout KeyedEncodingContainer<Key>) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(text, forKey: .text)
    }
}

/// The menus the header's pins open.
nonisolated enum PageHeaderMenu: String, Sendable {
    case status, parent
}

/// What the person did in the page's head, for the window to carry out.
enum PageHeaderEvent {
    case titleInput(ItemID, String)
    case titleCommit(ItemID, String, startWriting: Bool)
    case titleDiscard(ItemID)
    /// A pin asks for its menu, under the pin's frame in the editor's container.
    case menu(PageHeaderMenu, ItemID, CGRect)
    /// A row's or a pin's value asks for its editor under it, in the editor's container: the row's identifier.
    case edit(row: String, ItemID, CGRect)
    /// A row's or a pin's name was pressed, for the row's menu under the name in the editor's container: the row's
    /// identifier, and whether the value's own editor is reachable only from the menu.
    case fieldMenu(row: String, editsValue: Bool, ItemID, CGRect)
    /// The kicker's type name was pressed, for Change Type under it.
    case changeType(ItemID, CGRect)
    /// Hide from Page was chosen in the menu over Linked From: the row's identifier (`PagePlacement`) and the item the
    /// head was showing.
    case hideFromPage(row: String, ItemID)
    /// A row was dragged by its name: the whole order the page lists after the move, folded rows included.
    case moveRow(row: String, order: [String], ItemID)
}

/// SF Symbols the header shows, drawn here because the page cannot draw them itself. The page uses each as a mask,
/// so it takes the color of the text or the chip it is in.
nonisolated struct PageHeaderIcons: Encodable, Sendable {
    struct Icon: Encodable, Sendable {
        var url: String
        var width: Double
        var height: Double
    }

    var indicator: Icon
    /// The symbols of the property rows and of the four statuses by SF Symbol name, and the icons of the types by `TypeIconKey`.
    var symbols: [String: Icon]

    /// The symbol in the notice's close button, drawn small and bold as it is in the app's other small buttons.
    static let closeSymbol = "xmark"

    /// The symbol a tag's chip starts with, drawn at the size the app's tag chip draws it.
    static let tagSymbol = "number"

    /// The symbols at the size the rows' 13 point text gives them, following the interface's text size, and the
    /// icons of `typeIcons` (Iconify IDs), which the Swift SDK draws.
    @MainActor
    init?(textSize: Int, typeIcons: Set<String?>) {
        let size = 13 * InterfaceStyle.scale(for: textSize)
        if Self.drawn.textSize != textSize { Self.drawn = Drawn(textSize: textSize) }
        guard let indicator = Self.symbol("chevron.down", size: size * 0.7, weight: .bold) else { return nil }
        self.indicator = indicator
        var symbols: [String: Icon] = [:]
        for name in PropertyRow.Value.symbols + PageNotice.symbols {
            symbols[name] = Self.symbol(name, size: size, weight: .regular)
        }
        // The kicker's flags, at its 12 points.
        for flag in PageHead.Kicker.Flag.allCases {
            symbols[flag.symbol] = Self.symbol(flag.symbol, size: size * 11 / 13, weight: .regular)
        }
        symbols[Self.tagSymbol] = Self.symbol(
            Self.tagSymbol, size: ChipLooks.current.textSize * InterfaceStyle.scale(for: textSize) * 0.85, weight: .medium)
        symbols[Self.closeSymbol] = Self.symbol(Self.closeSymbol, size: size * 9 / 13, weight: .bold)
        // A status's four symbols at the size a status chip draws them, which the page uses as they come.
        for name in StatusSymbol.systemNames {
            symbols[name] = Self.symbol(name, size: StatusMark.size * InterfaceStyle.scale(for: textSize), weight: .regular)
        }
        for name in typeIcons {
            if Self.drawn.types[name] == nil { Self.drawn.types[name] = Self.typeIcon(name, size: size) }
            symbols[TypeIconKey.value(for: name)] = Self.drawn.types[name]
        }
        self.symbols = symbols
    }

    /// What has been drawn at the text size last asked for, so a window, an item or a type icon that appears later
    /// draws only what is new. A different text size draws everything again.
    private struct Drawn {
        var textSize: Int?
        /// By name, size and weight, since one symbol can be drawn two ways.
        var symbols: [String: Icon] = [:]
        var types: [String?: Icon] = [:]
    }

    @MainActor
    private static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight) -> Icon? {
        let key = "\(name)|\(size)|\(weight.rawValue)"
        if drawn.symbols[key] == nil { drawn.symbols[key] = icon(name, size: size, weight: weight) }
        return drawn.symbols[key]
    }

    @MainActor private static var drawn = Drawn()

    /// A type's icon as the page's mask: drawn black, since only its shape matters. With `square`, it is centered in a
    /// square of its longer side, so the page can scale it without distorting it. Shared by the header and the links
    /// in an item, so a type's icon is drawn one way.
    @MainActor
    static func typeIcon(_ name: String?, size: CGFloat, square: Bool = false) -> Icon? {
        Cost.measure(.iconDraw) { drawTypeIcon(name, size: size, square: square) }
    }

    @MainActor
    private static func drawTypeIcon(_ name: String?, size: CGFloat, square: Bool) -> Icon? {
        func glyph() -> some View { TypeGlyph(id: name).font(.system(size: size)).foregroundStyle(.black) }
        // Three times its size, as the symbols are.
        func render(_ content: some View) -> NSImage? {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            return renderer.nsImage
        }
        let image: NSImage?
        if square {
            guard let natural = render(glyph())?.size, natural.width > 0, natural.height > 0 else { return nil }
            let side = max(natural.width, natural.height).rounded(.up)
            image = render(glyph().frame(width: side, height: side))
        } else {
            image = render(glyph())
        }
        guard let image, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        return Icon(url: "data:image/png;base64," + png.base64EncodedString(),
                    width: Double(image.size.width), height: Double(image.size.height))
    }

    @MainActor
    private static func icon(_ name: String, size: CGFloat, weight: NSFont.Weight) -> Icon? {
        Cost.measure(.iconDraw) { drawSymbol(name, size: size, weight: weight) }
    }

    @MainActor
    private static func drawSymbol(_ name: String, size: CGFloat, weight: NSFont.Weight) -> Icon? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight, scale: .medium)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        else { return nil }
        // Drawn at three times its size, so it stays sharp on any display and at any page zoom.
        let scale: CGFloat = 3
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int((image.size.width * scale).rounded(.up)),
            pixelsHigh: Int((image.size.height * scale).rounded(.up)), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return Icon(url: "data:image/png;base64," + png.base64EncodedString(),
                    width: Double(image.size.width), height: Double(image.size.height))
    }
}
