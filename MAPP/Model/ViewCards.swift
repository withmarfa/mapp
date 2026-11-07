import Foundation

/// What a gallery draws on each card, as the person arranged it, for one view or for one place that is not a view.
/// The defaults draw a card as the gallery always has, so a view that never had these set looks the same.
nonisolated struct ViewCards: Codable, Hashable, Sendable {
    /// What fills the card's picture area.
    enum Preview: String, Codable, CaseIterable, Sendable {
        /// The item's picture, else a miniature of its page.
        case pictureOrText
        case picture
        case text
        /// No picture area: the card is its words alone.
        case none

        /// Whether a card of this preview has a picture to load, and so one to fit.
        var showsPicture: Bool { self == .pictureOrText || self == .picture }
    }

    enum Size: String, Codable, CaseIterable, Sendable {
        case small, medium, large

        /// The narrowest a card in this size is drawn, in points at the standard text size, which sets how many fit a row.
        var columnWidth: Double {
            switch self {
            case .small: 150
            case .medium: 190
            case .large: 260
            }
        }
    }

    /// The line under the title.
    enum Subtext: String, Codable, CaseIterable, Sendable {
        /// The type's mark, then the date the list is sorted by: the card as it has always read.
        case typeAndDate
        case type
        case date
        case none

        var showsType: Bool { self == .typeAndDate || self == .type }
        var showsDate: Bool { self == .typeAndDate || self == .date }
    }

    var preview = Preview.pictureOrText
    /// Whether a picture is shown whole, rather than filling the picture area and cut at its edges.
    var fitsPicture = false
    var size = Size.medium
    var subtext = Subtext.typeAndDate
    /// The properties shown under the subtext, in order, by `GalleryProperty.id`. One the place no longer offers is
    /// not drawn and not forgotten, since the items that hold it may come back.
    private(set) var properties: [String] = []

    init(
        preview: Preview = .pictureOrText, fitsPicture: Bool = false, size: Size = .medium, subtext: Subtext = .typeAndDate,
        properties: [String] = []
    ) {
        self.preview = preview
        self.fitsPicture = fitsPicture
        self.size = size
        self.subtext = subtext
        self.properties = properties
    }

    /// A choice this version does not know, or one a later version adds, never voids the rest.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preview = (try? container.decodeIfPresent(Preview.self, forKey: .preview)) ?? .pictureOrText
        fitsPicture = (try? container.decodeIfPresent(Bool.self, forKey: .fitsPicture)) ?? false
        size = (try? container.decodeIfPresent(Size.self, forKey: .size)) ?? .medium
        subtext = (try? container.decodeIfPresent(Subtext.self, forKey: .subtext)) ?? .typeAndDate
        properties = (try? container.decodeIfPresent([String].self, forKey: .properties)) ?? []
    }

    func shows(_ id: String) -> Bool {
        properties.contains(id)
    }

    /// Shows a property after the others, or hides it. The same arrangement is the same value however it was reached.
    mutating func setShown(_ id: String, _ isShown: Bool) {
        if isShown {
            if !properties.contains(id) { properties.append(id) }
        } else {
            properties.removeAll { $0 == id }
        }
    }

    /// Moves a shown property to sit before another, or last.
    mutating func move(_ id: String, before other: String?) {
        guard id != other, properties.contains(id) else { return }
        var moved = properties.filter { $0 != id }
        let index = other.flatMap { moved.firstIndex(of: $0) } ?? moved.count
        moved.insert(id, at: index)
        properties = moved
    }
}
