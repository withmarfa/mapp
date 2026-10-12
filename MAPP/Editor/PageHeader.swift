import AppKit

/// What the page's item header shows: the item's title, or the person's unsaved draft of it, and its chips. The
/// page draws it above the note so the two scroll as one surface; what it does stays native.
nonisolated struct PageHeader: Encodable, Equatable, Sendable {
    struct Chip: Encodable, Equatable, Sendable {
        var label: String
        var enabled: Bool
    }

    var item: String
    /// A deleted note shows a banner instead.
    var hidden: Bool
    var title: String
    var draft: String?
    var titleRejected: Bool
    var editable: Bool
    var type: String?
    var status: Chip?
    var parent: Chip?
    var propertyRejected: Bool
    var interfaceTextSize: Int
}

/// The menus the header's chips open.
nonisolated enum PageHeaderMenu: String, Sendable {
    case status, parent
}

/// What the person did in the page's header, for the window to carry out.
enum PageHeaderEvent {
    case titleInput(ItemID, String)
    case titleCommit(ItemID, String, startWriting: Bool)
    case titleDiscard(ItemID)
    /// A chip asks for its menu, under the chip's frame in the editor's container.
    case menu(PageHeaderMenu, ItemID, CGRect)
}

/// SF Symbols the header's chips show, drawn here because the page cannot draw them itself. The page uses each
/// as a mask, so it takes the chip's text color in light and dark.
nonisolated struct PageHeaderIcons: Encodable, Sendable {
    struct Icon: Encodable, Sendable {
        var url: String
        var width: Double
        var height: Double
    }

    var status: Icon
    var parent: Icon
    var indicator: Icon

    /// The symbols at the size SwiftUI gives them beside a label in the interface's body font.
    @MainActor
    init?(textSize: Int) {
        let size = NSFont.systemFontSize * InterfaceStyle.scale(for: textSize)
        guard let status = Self.icon("circle.lefthalf.filled", size: size, weight: .regular),
              let parent = Self.icon("square.stack", size: size, weight: .regular),
              let indicator = Self.icon("chevron.down", size: size * 0.6, weight: .bold)
        else { return nil }
        self.status = status
        self.parent = parent
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
