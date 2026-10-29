extension SourceChange {
    /// What the change is, for a signpost's name: never what it carries.
    nonisolated var kind: StaticString {
        switch self {
        case .loaded: "take.loaded"
        case .upserted: "take.upserted"
        case .removed: "take.removed"
        case .bodyChanged: "take.bodyChanged"
        case .answered: "take.answered"
        case .taken: "take.taken"
        case .catalogue: "take.catalogue"
        case .views: "take.views"
        case .unavailable: "take.unavailable"
        }
    }

    /// How many items (or views) the change names.
    nonisolated var itemCount: Int {
        switch self {
        case .loaded(let snapshot): snapshot.items.count
        case .upserted(let items): items.count
        case .removed(let ids): ids.count
        case .bodyChanged: 1
        case .views(let views): views.count
        case .answered, .taken, .catalogue, .unavailable: 0
        }
    }
}
