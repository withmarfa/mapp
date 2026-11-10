import Foundation

/// What a view's list takes of its own for its rows, where Settings otherwise decides: the row style, whether each row
/// shows a preview of the text, and whether pictures show. A choice is nil while the view follows Settings, and a switch
/// stores a value only when it differs from Settings, so the same arrangement is the same value however it was reached.
nonisolated struct ViewRows: Codable, Hashable, Sendable {
    /// The style every row takes in this view. Nil follows the type's own choice, then Settings.
    var style: ListRowStyle?
    private(set) var showsPreview: Bool?
    private(set) var showsPictures: Bool?

    init(style: ListRowStyle? = nil) {
        self.style = style
    }

    /// A field this version does not know, or one a later version adds, never voids the rest.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try? container.decodeIfPresent(ListRowStyle.self, forKey: .style)
        showsPreview = try? container.decodeIfPresent(Bool.self, forKey: .showsPreview)
        showsPictures = try? container.decodeIfPresent(Bool.self, forKey: .showsPictures)
    }

    /// The lines of text under each title, given the lines Settings shows. A preview the view turns on where Settings
    /// show none takes the standard number of lines.
    func previewLines(settings: Int) -> Int {
        guard let showsPreview else { return settings }
        if !showsPreview { return 0 }
        return settings > 0 ? settings : ListKey.defaultPreviewLines
    }

    func showsPictures(settings: Bool) -> Bool {
        showsPictures ?? settings
    }

    mutating func setShowsPreview(_ shows: Bool, settings: Int) {
        showsPreview = shows == (settings > 0) ? nil : shows
    }

    mutating func setShowsPictures(_ shows: Bool, settings: Bool) {
        showsPictures = shows == settings ? nil : shows
    }
}
