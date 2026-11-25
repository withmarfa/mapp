import Foundation

/// The family of core type an item's type builds on, where the app treats it apart: an event's time is its When row, a
/// person is drawn as a person where an item links to them, an item to read opens its original, and a web page is drawn
/// in SwiftUI. Every item's page has the same head (`PageHead`). A type nobody at WithMarfa defined takes the nearest
/// core type above it through the parents the catalogue names, so the app names no type a person or an app made.
nonisolated enum PageHeaderKind: String, Sendable {
    case general
    /// `core.event`: its time is one row, When.
    case event
    /// `core.entity.person`: a link to one is drawn as a person.
    case person
    /// `core.bookmark` and `core.media`: something to read, with an original to open.
    case reading
    /// `core.file.webpage`: the page itself. A file has no text to edit, so SwiftUI draws the head above the HTML
    /// (`WebPageItemPage`), from the same `PageHead` as the editor's.
    case webpage

    static func of(_ type: TypeID, in catalogue: Catalogue) -> PageHeaderKind {
        ([type] + catalogue.ancestors(of: type)).lazy.compactMap { builtIn[$0] }.first ?? .general
    }

    private static let builtIn: [TypeID: PageHeaderKind] = [
        TypeID("core.event"): .event,
        TypeID("core.entity.person"): .person,
        TypeID("core.bookmark"): .reading,
        TypeID("core.media"): .reading,
        TypeID("core.file.webpage"): .webpage,
    ]
}

extension ItemLibrary {
    /// The web address the corner's Open takes a page for reading to: the `url` of an item whose page is for reading.
    func originalAddress(of item: Item) -> URL? {
        guard PageHeaderKind.of(item.type, in: catalogue) == .reading else { return nil }
        return BrowserTarget.webAddress(item.value(of: "url")?.string?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Whether the item is a Web Page, which opens in the browser as a saved page.
    func isWebPage(_ item: Item) -> Bool { PageHeaderKind.of(item.type, in: catalogue) == .webpage }
}
