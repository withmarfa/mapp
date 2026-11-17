import Foundation

/// What a view decides about the gallery's cards, for one view or for one place that is not a view: the picture's
/// preview, whether it is fitted, and how large a card is. What a card says under its picture comes from its type's look
/// (`TypeLook`), never from the view.
nonisolated struct ViewCards: Codable, Hashable, Sendable {
    /// What fills the card's picture area.
    enum Preview: String, Codable, CaseIterable, Sendable {
        /// The item's picture, else its opening lines.
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

    /// The shape of the picture area, which sets how tall a card is for its width.
    enum Shape: String, Codable, CaseIterable, Sendable {
        /// Four wide to three high, as a photograph or a page.
        case standard
        case square
        /// Two wide to three high, as a book's cover.
        case cover

        /// Width over height.
        var aspect: Double {
            switch self {
            case .standard: 4.0 / 3.0
            case .square: 1
            case .cover: 2.0 / 3.0
            }
        }
    }

    var preview = Preview.pictureOrText
    /// Whether a picture is shown whole, rather than filling the picture area and cut at its edges.
    var fitsPicture = false
    var size = Size.medium
    var shape = Shape.standard

    init(preview: Preview = .pictureOrText, fitsPicture: Bool = false, size: Size = .medium, shape: Shape = .standard) {
        self.preview = preview
        self.fitsPicture = fitsPicture
        self.size = size
        self.shape = shape
    }

    /// A choice this version does not know, or one a later version adds, never voids the rest. The subtext and the
    /// properties an earlier version kept are not read: the look decides them now.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preview = (try? container.decodeIfPresent(Preview.self, forKey: .preview)) ?? .pictureOrText
        fitsPicture = (try? container.decodeIfPresent(Bool.self, forKey: .fitsPicture)) ?? false
        size = (try? container.decodeIfPresent(Size.self, forKey: .size)) ?? .medium
        shape = (try? container.decodeIfPresent(Shape.self, forKey: .shape)) ?? .standard
    }
}
