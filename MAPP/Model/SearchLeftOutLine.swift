import Foundation

/// The line that ends Search Items' results when items left out of search match too: how many more there are, and in
/// what. The count is of what one limited search found (`SearchResults.leftOutLimit`), so a full answer reads "At least".
nonisolated enum SearchLeftOutLine {
    /// The most names the line gives before it only says how many.
    static let namesShown = 3

    /// The line for `found`, the items the leave-out holds that match, or nil where there are none. `isCapped` is
    /// whether the search stopped at its limit.
    static func text(
        for found: [Item], isCapped: Bool, narrowing: SearchNarrowing, catalogue: Catalogue, sources: SourceDirectory
    ) -> String? {
        guard !found.isEmpty else { return nil }
        var names: [String] = []
        for item in found {
            let name: String
            switch narrowing.leftOutBy(item, in: catalogue) {
            case .source(let code): name = sources.name(code)
            case .type(let type): name = catalogue.plural(for: type)
            case nil: continue
            }
            if !names.contains(name) { names.append(name) }
        }
        let count = found.count
        guard !names.isEmpty, names.count <= namesShown else {
            return isCapped
                ? String(localized: "At least \(count) more left out of search.")
                : String(localized: "\(count) more left out of search.")
        }
        let list = names.formatted(.list(type: .and))
        return isCapped
            ? String(localized: "At least \(count) more in \(list), left out of search.")
            : String(localized: "\(count) more in \(list), left out of search.")
    }
}
