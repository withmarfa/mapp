import Foundation

/// Whether a picture at a web address is loaded for a note. The page fetches nothing itself: it asks the app, which
/// answers by this choice every time it is asked, so a change applies at once.
nonisolated enum RemotePictureSetting: String, CaseIterable, Identifiable, Sendable {
    /// Each picture waits for the person to choose to load it.
    case ask
    /// A picture in an item in the feed tier loads without asking. In the library tier, where the person's own notes
    /// are, it asks as Ask does. The feed tier is where connectors write and captures land, and also where a note made
    /// while the Inbox is selected lands (`MarfaLibrary.createItem`), so Always loads that note's pictures too.
    /// `Item.source` cannot tell these apart: every item carries the source of the key that wrote it, MAPP's included.
    case always
    /// No picture is fetched.
    case never

    static let key = "remotePictures"
    static let standard = RemotePictureSetting.ask

    var id: Self { self }

    static func current(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? standard
    }
}
