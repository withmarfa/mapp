import Foundation

/// What the corner's Open takes an item's page to, outside the app: the address of a bookmark or a web page in the
/// browser, a file in the app that opens it, or a place in Maps. A page has at most one; text that stays in the app has
/// none.
nonisolated enum PageOpenTarget: Equatable, Sendable {
    /// The page's own web address, in the default browser.
    case address(URL)
    /// A Web Page's saved file, which the browser is given a copy of (`PageOpener`).
    case savedPage(URL)
    /// A file, in the app that opens it.
    case file(URL)
    /// A place's point, in Maps.
    case point(LocationPoint)

    /// The target of `item`'s page, or nil where there is none. `file` is the item's file once the window has it. A file
    /// opens as a file, whatever else it holds.
    @MainActor
    static func of(_ item: Item, in library: any ItemLibrary, file: URL?) -> PageOpenTarget? {
        if item.isFile, library.pageLayout(of: item) == .file { return file.map(PageOpenTarget.file) }
        switch PageHeaderKind.of(item.type, in: library.catalogue) {
        case .webpage:
            switch BrowserTarget.of(item, fetchedFile: file) {
            case .address(let address): return .address(address)
            case .file(let saved): return .savedPage(saved)
            case nil: return nil
            }
        case .reading:
            return library.originalAddress(of: item).map(PageOpenTarget.address)
        case .general, .event, .person, .place:
            guard let location = ItemLocation.of(library.catalogue.itemTypes[item.type]),
                  case .point(let point) = location.reading(of: item) else { return nil }
            return .point(point)
        }
    }

    /// The address Maps opens for a point.
    static func mapsAddress(for point: LocationPoint) -> URL? {
        URL(string: "maps://?ll=\(point.latitude),\(point.longitude)")
    }
}
