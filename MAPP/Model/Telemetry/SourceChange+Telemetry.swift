extension SourceChange {
    /// What the change is, for a signpost's name: never what it carries.
    nonisolated var kind: StaticString {
        switch self {
        case .loaded: "take.loaded"
        case .changed: "take.changed"
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
        case .changed(let changes): Set(changes.upserted.map(\.id) + changes.removed + changes.bodies.map(\.id)).count
        case .views(let views): views.count
        case .answered, .taken, .catalogue, .unavailable: 0
        }
    }
}
