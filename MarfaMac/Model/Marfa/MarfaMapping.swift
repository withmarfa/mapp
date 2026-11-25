import Foundation
import Marfa
import os

/// Reads the package's values into the item layer's. Pure, so the rules are tested on values made by hand.
nonisolated enum MarfaMapping {
    static let fileType = TypeID.file
    /// The core.file fields naming the bytes, their kind and their length, which the server sets.
    static let blobField = "blob_ref"
    static let mimeTypeField = "mime_type"
    static let sizeField = "size_bytes"
    static let widthField = "width"
    static let heightField = "height"
    /// The file’s blob reference, kind, size, and values Marfa reads from the bytes (`READ_FROM_BYTES`).
    static let fileFacts: Set<String> = [blobField, mimeTypeField, sizeField, "extracted_text", widthField, heightField, durationField]
    /// Marfa's folder device writes a body link as this edge, so it reads as the body's, not a property's.
    static let bodyLinkEdge = "references"
    /// Marfa writes an embed of a file as this edge, from the file's item to the item whose body embeds it.
    static let attachmentEdge = "attached-to"
    static let parentEdge = "parent-of"
    /// Marfa places an item in a synced folder with this edge, from the item to the folder; its `path` is the file
    /// the item is written to, whose name a link or an embed may name the item by.
    static let placementEdge = "in-folder"
    /// Marfa files an item in a collection with this edge, from the member to the collection.
    static let collectionEdge = "in-collection"
    /// The role a type plays to be a collection, which `in-collection` names at its to item.
    static let containerRole = "container"
    /// How a merge verdict names the item's tier among the fields it resolved.
    static let tierField = "tier"
    /// The type a task is, or descends from: only such a type's `priority` and `due_at` are read as a priority and a
    /// due date.
    static let taskType = TypeID("core.task")
    static let priorityField = "priority"
    static let dueField = "due_at"
    /// A task's people.
    static let assigneesField = "assignees"
    /// Where a `core.highlight`'s passage starts.
    static let startLocationField = "start_location"
    static let highlightType = TypeID("core.highlight")
    /// The type an event is, or descends from; with a task, the types whose `starts_at` is read as a start date.
    static let eventType = TypeID("core.event")
    static let startField = "starts_at"
    /// Where an event or a session ends, which the table's hidden Duration column reads with `startField`.
    static let endField = "ends_at"
    /// The fields a look's presets read (`LookPreset`). Some are Marfa's core names (`from`, `emails`, `street_address`);
    /// the others (`project`, `category`) are what a connector's or a person's type may carry. A type that has
    /// none of them has an empty place, never a guess.
    static let fromField = "from"
    static let projectField = "project"
    static let repositoryField = "repository"
    static let placeField = "place"
    static let attendeesField = "attendees"
    static let jobTitleField = "job_title"
    static let organizationField = "organization"
    static let emailsField = "emails"
    static let phonesField = "phones"
    static let streetAddressField = "street_address"
    static let localityField = "locality"
    static let postalCodeField = "postal_code"
    static let latitudeField = "latitude"
    static let longitudeField = "longitude"
    static let categoryField = "category"
    static let passageField = "text"
    static let publishedField = "published_at"
    static let durationField = "duration"
    static let authorField = "author"
    static let urlField = "url"
    /// What a clipboard item would name for the app it came from; no shipped type has it.
    static let sourceAppField = "source_app"

    /// The `in-collection` property that orders a collection's members.
    static let positionProperty = "position"

    /// Marfa keeps what apps share, such as saved views, as `system.*` rows, and what one app keeps for itself, such as
    /// the app's own settings, as `app.*` rows; neither is an item of the library. The copy holds `system.view` so the
    /// sidebar can list the views, and `app.marfa-mac.preferences` for `PreferencesSync` (`MarfaSync.slice`).
    static func isLibraryItem(_ row: Marfa.Item) -> Bool { !TypeID.isHidden(row.type) }

    /// A view still in use, as the sidebar lists it.
    static func view(_ view: SavedView) -> LibraryView? {
        guard view.state != .revoked else { return nil }
        let settings = view.settings
        let query = settings.query
        return LibraryView(
            id: ItemID(view.id), title: settings.title, version: view.version,
            query: LibraryViewQuery(
                types: query.types.map { TypeID($0) },
                tier: query.tier.flatMap(viewTier),
                states: query.states.map { Set($0.map(state)) },
                filter: query.filter, beneath: query.beneath.map { ItemID($0) }),
            sort: settings.sort.map { LibraryViewSort(field: $0.by, ascending: $0.direction == .ascending) },
            group: settings.group.map(libraryGroup))
    }

    private static func libraryGroup(_ group: ViewGrouping) -> LibraryViewGroup {
        let known = group.bucket.flatMap { LibraryViewGroup.Bucket(rawValue: $0.rawValue) }
        return LibraryViewGroup(
            field: group.by, bucket: known, order: group.order, hidden: group.hidden,
            otherBucket: known == nil ? group.bucket?.rawValue : nil)
    }

    /// Nil where a view lists both tiers.
    private static func viewTier(_ tier: SliceTier) -> Tier? {
        switch tier {
        case .library: .library
        case .feed: .feed
        case .all: nil
        }
    }

    private static func marfaBucket(_ group: LibraryViewGroup) -> ViewGrouping.Bucket? {
        (group.bucket?.rawValue ?? group.otherBucket).map(ViewGrouping.Bucket.init(rawValue:))
    }

    static func viewSettings(_ settings: LibraryViewSettings) -> ViewSettings {
        ViewSettings(
            title: settings.title, query: viewQuery(settings.query), sort: settings.sort.map(viewSort),
            group: settings.group.map(viewGrouping))
    }

    static func viewChange(_ change: LibraryViewChange) -> ViewSettingsChange {
        ViewSettingsChange(
            title: change.title, query: change.query.map(viewQuery), sort: change.sort.map { $0.map(viewSort) },
            group: change.group.map { grouping in
                switch grouping {
                case .set(let group): .set(viewGrouping(group))
                case .clear: .clear
                }
            })
    }

    private static func viewQuery(_ query: LibraryViewQuery) -> ViewQuery {
        ViewQuery(
            types: query.types.map(\.rawValue),
            tier: query.tier.map { $0 == .feed ? SliceTier.feed : .library },
            // Ordered, so one query is always sent alike.
            states: query.states.map { states in [ItemState.active, .archived, .trashed].filter(states.contains).map(marfaState) },
            filter: query.filter, beneath: query.beneath?.rawValue)
    }

    /// What the copy is asked to list for a view's query read as the copy lists items. A view with no states lists
    /// active and archived items, while a list with none lists the active ones, so they are named here.
    static func listFilters(_ query: LibraryViewQuery) -> ListFilters {
        ListFilters(
            types: query.types.isEmpty ? nil : Set(query.types.map(\.rawValue)),
            states: Set((query.states ?? [.active, .archived]).map(marfaState)),
            tier: query.tier.map { $0 == .feed ? Marfa.Tier.feed : .library },
            filter: query.filter, beneath: query.beneath?.rawValue)
    }

    private static func viewSort(_ sort: LibraryViewSort) -> ViewSort {
        ViewSort(by: sort.field, direction: sort.ascending ? .ascending : .descending)
    }

    private static func viewGrouping(_ group: LibraryViewGroup) -> ViewGrouping {
        ViewGrouping(by: group.field, bucket: marfaBucket(group), order: group.order, hidden: group.hidden)
    }

    /// The server's refusal of a view write, in words for the person. A view is written at once, so a server that
    /// cannot be reached saved nothing.
    static func viewFailure(_ error: any Error) -> ViewWriteFailure {
        guard let error = MarfaServerCalls.marfaError(in: error) else {
            Telemetry.logger(.library).error("A view write failed: \(String(describing: error))")
            return ViewWriteFailure(kind: .refused, message: Words.syncFailed)
        }
        if error.isOffline {
            return ViewWriteFailure(kind: .offline, message: String(localized: "The app can’t reach your Marfa server, so nothing was saved. Try again when it’s back."))
        }
        switch error {
        case .noServer:
            return ViewWriteFailure(kind: .offline, message: String(localized: "The app can’t reach your Marfa server, so nothing was saved. Try again when it’s back."))
        case .versionConflict:
            return ViewWriteFailure(kind: .conflict, message: String(localized: "This view was changed elsewhere since this window read it, so nothing was saved. The window now shows the view as it is; make your changes again."))
        case .notFound:
            return ViewWriteFailure(kind: .gone, message: String(localized: "Your Marfa server no longer has this view."))
        case .forbidden:
            return ViewWriteFailure(kind: .notPermitted, message: String(localized: "The app’s sign-in can’t change views on your Marfa server."))
        case .validation(_, let message, _, _):
            return ViewWriteFailure(kind: .refused, message: message)
        default:
            return ViewWriteFailure(kind: .refused, message: Words.message(for: error))
        }
    }
}
