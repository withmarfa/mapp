import AppKit
import MarfaIcons
import SwiftUI

/// What the page's item header shows: the item's title, or the person's unsaved draft of it, and its pinned
/// properties. The page draws it above the note so the two scroll as one surface; what it does stays native.
nonisolated struct PageHeader: Encodable, Equatable, Sendable {
    /// A status's ring: its color and how much of it is filled. The catalogue holds neither, so they follow the
    /// status's tone (`StatusTone`), and a status the app does not know gets the plain ring.
    struct Mark: Encodable, Equatable, Sendable {
        enum Tone: String, Encodable, Sendable { case neutral, orange, red, green, grey }
        enum Fill: String, Encodable, Sendable { case none, half, full }
        var tone: Tone
        var fill: Fill

        init(tone: Tone, fill: Fill) {
            self.tone = tone
            self.fill = fill
        }

        init(status: String?) {
            switch status.map(StatusTone.init) {
            case .active: self.init(tone: .orange, fill: .half)
            case .waiting: self.init(tone: .red, fill: .half)
            case .done: self.init(tone: .green, fill: .full)
            case .canceled: self.init(tone: .grey, fill: .full)
            case .planned, .later, .other, nil: self.init(tone: .neutral, fill: .none)
            }
        }
    }

    /// A pin that opens a menu. An empty one has no value yet: the page shows a plus and a quieter edge. A pin
    /// that opens the app's chooser directly, as an empty parent does, is not a menu and has no chevron.
    struct Pin: Encodable, Equatable, Sendable {
        var label: String
        var enabled: Bool
        var empty = false
        var opensMenu = true
        var mark: Mark?
    }

    /// A type's icon as the page names it among the images the app sends (`TypeIconKey`), and the Lucide name the app
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
    var type: String?
    /// The icon of the item's type, drawn before its name.
    var icon: TypeIconRef
    /// Which header the page draws, chosen from the core type the item's type builds on.
    var kind: PageHeaderKind
    var event: EventHeader?
    var person: PersonHeader?
    /// The line under the title: a person's work, or a reading item's description.
    var subtitle: String?
    var status: Pin?
    var parent: Pin?
    var byline: PageByline
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
    var propertyRejected: Bool
    var parentRejected: Bool
    var interfaceTextSize: Int
}

extension PropertyRow: Encodable {
    private enum Key: String, CodingKey { case id, label, symbol, kind, text, texts, items }
    private struct Link: Encodable {
        let title: String
        let item: String
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(value.symbol, forKey: .symbol)
        switch value {
        case .status: try container.encode("status", forKey: .kind)
        case .parent: try container.encode("parent", forKey: .kind)
        case .items(let targets):
            try container.encode("items", forKey: .kind)
            try container.encode(targets.map { Link(title: $0.title, item: $0.item.rawValue) }, forKey: .items)
        case .tags(let tags):
            try container.encode("tags", forKey: .kind)
            try container.encode(tags, forKey: .texts)
        case .date(let text): try Self.encode("date", text, into: &container)
        case .url(let text): try Self.encode("url", text, into: &container)
        case .email(let text): try Self.encode("email", text, into: &container)
        case .phone(let text): try Self.encode("phone", text, into: &container)
        case .boolean(let flag):
            try Self.encode("text", flag ? String(localized: "Yes") : String(localized: "No"), into: &container)
        case .text(let text): try Self.encode("text", text, into: &container)
        }
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
}

/// SF Symbols the header's pins show, drawn here because the page cannot draw them itself. The page uses each
/// as a mask, so it takes the pin's secondary color in light and dark.
nonisolated struct PageHeaderIcons: Encodable, Sendable {
    struct Icon: Encodable, Sendable {
        var url: String
        var width: Double
        var height: Double
    }

    var parent: Icon
    var plus: Icon
    var indicator: Icon
    /// The symbols of the property rows by SF Symbol name, and the icons of the types by `TypeIconKey`.
    var symbols: [String: Icon]

    /// The symbols at the size the pins' 12 point text gives them, following the interface's text size, and the
    /// icons of `typeIcons` (Lucide names), which the Swift SDK draws.
    @MainActor
    init?(textSize: Int, typeIcons: Set<String?>) {
        let size = 13 * InterfaceStyle.scale(for: textSize)
        if Self.drawn.textSize != textSize { Self.drawn = Drawn(textSize: textSize) }
        guard let parent = Self.symbol("square.stack", size: size, weight: .regular),
              let plus = Self.symbol("plus", size: size, weight: .regular),
              let indicator = Self.symbol("chevron.down", size: size * 0.7, weight: .bold)
        else { return nil }
        self.parent = parent
        self.plus = plus
        self.indicator = indicator
        var symbols: [String: Icon] = [:]
        for name in PropertyRow.Value.symbols {
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

    /// A type's icon as the page's mask: drawn black, since only its shape matters.
    @MainActor
    private static func typeIcon(_ name: String?, size: CGFloat) -> Icon? {
        Cost.measure(.iconDraw) { drawTypeIcon(name, size: size) }
    }

    @MainActor
    private static func drawTypeIcon(_ name: String?, size: CGFloat) -> Icon? {
        let renderer = ImageRenderer(content: TypeIcon(name: name).font(.system(size: size)).foregroundStyle(.black))
        // Three times its size, as the symbols are.
        renderer.scale = 3
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
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
