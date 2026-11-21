import Foundation

/// What the right sidebar asks for when nothing is chosen, by what the place lists.
nonisolated enum InspectorPrompt: Equatable {
    case item, event, collection, source

    /// The prompt for an item list, which a calendar layout words for events.
    static func forItems(in mode: ItemViewMode) -> InspectorPrompt { mode == .calendar ? .event : .item }

    /// The prompt for an index page of containers.
    static func forIndex(_ place: IndexPlace) -> InspectorPrompt {
        switch place {
        case .items: .item
        case .collections: .collection
        case .sources: .source
        }
    }

    /// How long a chosen item that is still being read goes before the sidebar shows a progress indicator, so a read that
    /// ends at once shows none.
    static let progressDelay = Duration.milliseconds(500)
}
