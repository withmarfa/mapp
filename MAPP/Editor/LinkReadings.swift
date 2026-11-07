import SwiftUI

/// What the library says a link in a note means, for the page to draw it: whether it names no note and, when it names
/// exactly one, the type of that note.
nonisolated struct LinkReading: Equatable, Sendable {
    /// The type of the one note the link names.
    struct LinkedType: Equatable, Sendable {
        /// The Iconify ID of the type's icon; nil for a type the catalogue gives none.
        var icon: String?
        var tone: TypeTone
    }

    var missing: Bool
    /// Nil for a link to no note and for one that does not name exactly one, which the page draws without a mark.
    var type: LinkedType?

    /// A link drawn as a live one with no mark: what the page assumes when the library cannot say.
    static let plain = LinkReading(missing: false, type: nil)
}

extension ItemLibrary {
    /// What each of `targets` (link texts as authored, brackets and all) means from `note`, in order, or nil where the
    /// library cannot ask. A link names one note only when the core binds it (`LinkAnswer.state`); an ambiguous or
    /// unresolved one has no single type, and a note in the bin is not named at all, so its link reads as missing.
    func linkReadings(of targets: [String], in note: ItemID) async -> [LinkReading]? {
        guard let answers = await linkAnswers(of: targets, in: note), answers.count == targets.count else { return nil }
        return answers.map { answer in
            if answer.isMissing { return LinkReading(missing: true, type: nil) }
            guard answer.state == .bound, let id = answer.item, let item = item(id) else { return .plain }
            let icon = catalogue.icon(for: item.type)
            return LinkReading(missing: false, type: .init(icon: icon, tone: TypeTone(icon: icon)))
        }
    }
}

/// The reply to the page's `resolve` request: an entry for each link posted, in order, and the image of each type icon
/// the entries name, once however many entries name it.
nonisolated struct LinkReply: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var missing: Bool
        /// A key of `icons`, absent for a link with no icon to draw.
        var icon: String?
        var tone: String?

        init(missing: Bool, icon: String? = nil, tone: String? = nil) {
            self.missing = missing
            self.icon = icon
            self.tone = tone
        }
    }

    var links: [Entry]
    var icons: [String: String]

    /// The reply as the web view carries it.
    var propertyList: [String: Any] {
        [
            "links": links.map { entry -> [String: Any] in
                var dictionary: [String: Any] = ["missing": entry.missing]
                if let icon = entry.icon { dictionary["icon"] = icon }
                if let tone = entry.tone { dictionary["tone"] = tone }
                return dictionary
            },
            "icons": icons,
        ]
    }

    /// The reply for `readings`, drawing each distinct icon once with `draw`. An icon that cannot be drawn leaves its
    /// links with their tone and no icon.
    init(_ readings: [LinkReading], draw: (String?) -> String?) {
        var icons: [String: String] = [:]
        var failed: Set<String> = []
        links = readings.map { reading in
            guard !reading.missing, let type = reading.type else { return Entry(missing: reading.missing) }
            let key = TypeIconKey.value(for: type.icon)
            if icons[key] == nil, !failed.contains(key) {
                if let url = draw(type.icon) { icons[key] = url } else { failed.insert(key) }
            }
            return Entry(missing: false, icon: icons[key] == nil ? nil : key, tone: type.tone.rawValue)
        }
        self.icons = icons
    }
}

/// The type icons the page draws before a link, as images it masks in the type's color. Each is drawn once, black on
/// clear, into a square so the page can scale it without distorting it.
@MainActor
enum LinkIcons {
    private static var drawn: [String?: String] = [:]
    private static let fontSize: CGFloat = 16

    /// A data URL of the icon's PNG, nil where it cannot be drawn.
    static func dataURL(for icon: String?) -> String? {
        if let known = drawn[icon] { return known }
        guard let url = Cost.measure(.iconDraw, { draw(icon) }) else { return nil }
        drawn[icon] = url
        return url
    }

    private static func draw(_ icon: String?) -> String? {
        func glyph() -> some View { TypeGlyph(id: icon).font(.system(size: fontSize)).foregroundStyle(.black) }
        let measure = ImageRenderer(content: glyph())
        guard let natural = measure.nsImage?.size, natural.width > 0, natural.height > 0 else { return nil }
        let side = max(natural.width, natural.height).rounded(.up)
        let renderer = ImageRenderer(content: glyph().frame(width: side, height: side))
        // Three times its size, as the header's icons are, so it stays sharp at any zoom.
        renderer.scale = 3
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }
}
