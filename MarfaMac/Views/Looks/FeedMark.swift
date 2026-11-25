import SwiftUI

/// The Feed's mark, after the name of a Feed item in a list of both tiers (`RowContent.inFeed`): the symbol of Move to
/// Feed in tertiary gray, so it follows the text and the appearance. A name on one line keeps its mark whole while its
/// words shorten (`FeedMark()`); a name that wraps carries it as its last word (`titled`).
struct FeedMark: View {
    var body: some View {
        Image(systemName: Self.symbol)
            .interfaceFont(.body)
            .imageScale(.small)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Feed")
    }

    private static let symbol = ItemMove.moveToFeed.symbol

    /// A title that may wrap, with the mark after its last word.
    static func titled(_ title: String) -> Text {
        Text("\(Text(verbatim: title)) \(Text(Image(systemName: symbol)).foregroundStyle(.tertiary))")
    }
}
