import AppKit
import MarfaIcons
import SwiftUI

/// What the page's item header shows: the item's title, or the person's unsaved draft of it, its pinned properties
/// (`PagePins`) and the rows of the property block. The page draws it above the note so the two scroll as one
/// surface; what it does stays native.
nonisolated struct PageHeader: Encodable, Equatable, Sendable {
    /// A status's ring: its color and how it is filled. The catalogue holds neither, so they follow the group the
    /// type puts it in, and a status no group claims gets the plain ring. A tone is one of `TypeTone`'s names, or
    /// `neutral` for the ring in the text's own color.
    struct Mark: Encodable, Hashable, Sendable {
        enum Tone: String, Encodable, Sendable { case neutral, blue, green, red, gray }
        enum Fill: String, Encodable, Sendable { case none, half, full, slash }
        var tone: Tone
        var fill: Fill

        init(tone: Tone, fill: Fill) {
            self.tone = tone
            self.fill = fill
        }

        init(group: StatusGroup?) {
            switch group {
            case .inProgress: self.init(tone: .blue, fill: .half)
            case .completed: self.init(tone: .green, fill: .full)
            case .canceled: self.init(tone: .gray, fill: .slash)
            case .notStarted, nil: self.init(tone: .neutral, fill: .none)
            }
        }
    }

    /// The status or the parent as the menu the page opens from it, wherever the page draws it. The page draws the
    /// button; the app builds the menu. An empty status, in the property block, has no value yet: the page reads it
    /// as every empty value reads, and `label` is then unused. A parent exists only with a value.
    struct Pin: Encodable, Equatable, Sendable {
        var label: String
        var enabled: Bool
        var empty = false
        /// Only the status pin has a mark.
        var mark: Mark?
        /// Only the parent pin has these: the parent's type icon and the tone of its chip, as a linked item's has.
        var icon: TypeIconRef?
        var tone: String?
    }

    /// Every chip look as CSS custom properties for the page, resolved for light and for dark so an appearance
    /// change needs no resend: the sizes and fills (`ChipLooks.cssVariables`) and each tone's colors as
    /// `--tone-<name>`, `--tone-<name>-ink`, `--tone-<name>-mark` and `--tone-<name>-chip`. A chip names its tone and the page forwards the name.
    struct ChipStyle: Encodable, Equatable, Sendable {
        var light: [String: String]
        var dark: [String: String]

        @MainActor
        init(looks: ChipLooks = .current) {
            func variables(dark: Bool) -> [String: String] {
                var all = ChipLooks.cssVariables(dark: dark, looks: looks)
                for tone in TypeTone.allCases {
                    for (name, value) in TypeTone.cssColors(for: tone, dark: dark, looks: looks) {
                        all["--tone-\(tone.rawValue)\(name.dropFirst("--tone".count))"] = value
                    }
                }
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

    var item: String
    /// A deleted note shows a banner instead.
    var hidden: Bool
    var title: String
    var draft: String?
    var titleRejected: Bool
    /// Why a title is refused, which depends on the library.
    var titleRefusal: String
    var editable: Bool
    /// False where the item is titled by the first line of its text, which the page already shows as its text.
    var showsTitle = true
    /// Which header the page draws, chosen from the core type the item's type builds on.
    var kind: PageHeaderKind
    var person: PersonHeader?
    /// The line under the title: a person's work, or a reading item's description.
    var subtitle: String?
    /// The status menu, for the status row or pin, which holds it; nil where the type has none.
    var status: Pin?
    /// The parent menu, for the parent row; nil where the item has no parent.
    var parent: Pin?
    /// The pinned properties under the title, in the order the person chose, at most four.
    var pins: [PropertyRow]
    /// A reading item's line above the title: its source, when it was published and how long it takes. No other
    /// page has one.
    var byline: PageByline?
    /// The property block's rows, all of them; the page shows the first `foldAfter` until it is expanded.
    var properties: [PropertyRow]
    var foldAfter = PropertyRow.foldAfter
    /// The items a collection holds, listed under its text; none for any other item.
    var contents: [LinkedItem]
    /// Items that link to this one, listed under its text.
    var linked: [LinkedItem]
    var linkedFoldAfter = LinkedItem.foldAfter
    /// Whether the page has text to write. A collection with no text shows its contents in place of an empty page.
    var showsText: Bool
    /// "Show N More", for the rows and for the items that are folded away.
    var showMore: String
    var showMoreContents: String
    var showMoreLinked: String
    var interfaceTextSize: Int
    /// How many lines the title shows before an ellipsis cuts it, while it is not being edited.
    var titleLines: Int
    var chips: ChipStyle
    /// How many items link to this one, for the row above the title, wherever Linked From is placed.
    var linkedCount = 0
    /// Customize Layout in the row above the title: nil where the item cannot be laid out, else whether it is on.
    var layoutOn: Bool?

    /// The icons of the types the header names, which the page draws as images.
    var typeIconNames: Set<String?> {
        var names: Set<String?> = []
        names.formUnion((contents + linked).map(\.icon))
        if let parent = parent?.icon { names.insert(parent.name) }
        for value in (pins + properties).map(\.value) {
            switch value {
            case .items(let targets): names.formUnion(targets.map(\.icon))
            case .type(_, let icon): names.insert(icon)
            default: break
            }
        }
        return names
    }
}

extension PropertyRow: Encodable {
    private enum Key: String, CodingKey { case id, label, symbol, kind, text, texts, items, options, people, icon, tone, more, help, editable }
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
    }
    private struct Option: Encodable {
        let label: String
        let tone: String
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(value.symbol, forKey: .symbol)
        switch value {
        case .status: try container.encode("status", forKey: .kind)
        case .empty: try container.encode("empty", forKey: .kind)
        case .parent: try container.encode("parent", forKey: .kind)
        case .type(let name, let icon):
            try Self.encode("type", name, into: &container)
            try container.encode(TypeIconKey.value(for: icon), forKey: .icon)
            try container.encode(TypeTone(icon: icon).rawValue, forKey: .tone)
        case .source(let name): try Self.encode("text", name, into: &container)
        case .items(let targets):
            try container.encode("items", forKey: .kind)
            try container.encode(targets.map(Link.init), forKey: .items)
        case .people(let names):
            try container.encode("people", forKey: .kind)
            try container.encode(names.map { Listed(title: $0, initials: PersonInitials.of($0)) }, forKey: .people)
        case .options(let options):
            try container.encode("options", forKey: .kind)
            try container.encode(
                options.enumerated().map { Option(label: $1, tone: (optionTones.indices.contains($0) ? optionTones[$0] : OptionTone.tone(for: $1)).rawValue) },
                forKey: .options)
        case .tags(let tags):
            try container.encode("tags", forKey: .kind)
            try container.encode(tags, forKey: .texts)
        case .date(let text): try Self.encode("date", text, into: &container)
        case .when(let text, let help):
            try Self.encode("date", text, into: &container)
            try container.encode(help, forKey: .help)
        case .url(let text): try Self.encode("url", text, into: &container)
        case .email(let text): try Self.encode("email", text, into: &container)
        case .phone(let text): try Self.encode("phone", text, into: &container)
        case .boolean(let flag):
            try Self.encode("text", flag ? String(localized: "Yes") : String(localized: "No"), into: &container)
        case .text(let text): try Self.encode("text", text, into: &container)
        }
        if more > 0 { try container.encode(more, forKey: .more) }
        if editable { try container.encode(true, forKey: .editable) }
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

/// What the person did in the page's header, for the window to carry out.
enum PageHeaderEvent {
    case titleInput(ItemID, String)
    case titleCommit(ItemID, String, startWriting: Bool)
    case titleDiscard(ItemID)
    /// A pin asks for its menu, under the pin's frame in the editor's container.
    case menu(PageHeaderMenu, ItemID, CGRect)
    /// A row's or a pin's value asks for its editor under it, in the editor's container: the row's identifier.
    case edit(row: String, ItemID, CGRect)
    /// Hide from Page was chosen in the menu over a row of the property block, or Linked From: the row's
    /// identifier (`PagePlacement`) and the item the header was showing.
    case hideFromPage(row: String, ItemID)
    /// A row of the property block was dragged by its key: the whole order the page shows after the move, folded rows
    /// included.
    case moveRow(row: String, order: [String], ItemID)
    /// Customize Layout in the row above the title was pressed.
    case toggleLayout
    /// Linked From in the row above the title was pressed, to see what links here.
    case showLinked
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
    /// The symbols of the property rows by SF Symbol name, and the icons of the types by `TypeIconKey`.
    var symbols: [String: Icon]

    /// The symbol on the callout that says pictures at web addresses are not loaded, kept with the row symbols.
    static let pictureSymbol = "photo"

    /// The symbols of the row above the title: Linked From and Customize Layout.
    static let titleToolSymbols = ["arrow.down.left", "rectangle.split.2x1"]

    /// What a row's key shows under the pointer, to say it can be dragged.
    static let rowGripSymbol = "line.3.horizontal"

    /// The symbols at the size the pins' 12 point text gives them, following the interface's text size, and the
    /// icons of `typeIcons` (Iconify IDs), which the Swift SDK draws.
    @MainActor
    init?(textSize: Int, typeIcons: Set<String?>) {
        let size = 13 * InterfaceStyle.scale(for: textSize)
        if Self.drawn.textSize != textSize { Self.drawn = Drawn(textSize: textSize) }
        guard let indicator = Self.symbol("chevron.down", size: size * 0.7, weight: .bold) else { return nil }
        self.indicator = indicator
        var symbols: [String: Icon] = [:]
        for name in PropertyRow.Value.symbols + [Self.pictureSymbol, Self.rowGripSymbol] + Self.titleToolSymbols {
            symbols[name] = Self.symbol(name, size: size, weight: .regular)
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
    /// in a note, so a type's icon is drawn one way.
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
