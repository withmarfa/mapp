import Foundation
import Marfa

/// What a page to read shows besides its title: a description to stand under the title. The source and the day it was
/// published are properties, like any other page's.
nonisolated struct ReadingHeader: Equatable, Sendable {
    /// The item's description, read as the page's dek.
    let dek: String?

    /// The properties the header draws, and `image_url`, which it leaves out: the page loads nothing from the network,
    /// and a bare image address reads as clutter above an article. The inspector still shows it.
    static let keys: Set<String> = ["description", "image_url"]

    init(item: Item) {
        func text(_ key: String) -> String? {
            item.value(of: key)?.string.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        dek = text("description")
    }

    static func webAddress(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()), url.host() != nil
        else { return nil }
        return url
    }
}
