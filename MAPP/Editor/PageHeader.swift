import AppKit

/// What the page's item header shows: the item's title, or the person's unsaved draft of it, and its pinned
/// properties. The page draws it above the note so the two scroll as one surface; what it does stays native.
nonisolated struct PageHeader: Encodable, Equatable, Sendable {
    /// A status's ring: its color and how much of it is filled. The catalogue holds neither, so they follow the
    /// status's name, and a status the app does not know gets the plain ring.
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
            switch status {
            case "in_progress": self.init(tone: .orange, fill: .half)
            case "blocked": self.init(tone: .red, fill: .half)
            case "completed": self.init(tone: .green, fill: .full)
            case "canceled": self.init(tone: .grey, fill: .full)
            default: self.init(tone: .neutral, fill: .none)
            }
        }
    }

    /// A pin that opens a menu. An empty one has no value yet: the page shows a plus and a quieter edge.
    struct Pin: Encodable, Equatable, Sendable {
        var label: String
        var enabled: Bool
        var empty = false
        var mark: Mark?
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
    var status: Pin?
    var parent: Pin?
    var propertyRejected: Bool
    var interfaceTextSize: Int
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

    var type: Icon
    var parent: Icon
    var plus: Icon
    var indicator: Icon

    /// The symbols at the size the pins' 12 point text gives them, following the interface's text size.
    @MainActor
    init?(textSize: Int) {
        let size = 13 * InterfaceStyle.scale(for: textSize)
        guard let type = Self.icon("doc.text", size: size, weight: .regular),
              let parent = Self.icon("square.stack", size: size, weight: .regular),
              let plus = Self.icon("plus", size: size, weight: .regular),
              let indicator = Self.icon("chevron.down", size: size * 0.7, weight: .bold)
        else { return nil }
        self.type = type
        self.parent = parent
        self.plus = plus
        self.indicator = indicator
    }

    @MainActor
    private static func icon(_ name: String, size: CGFloat, weight: NSFont.Weight) -> Icon? {
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
