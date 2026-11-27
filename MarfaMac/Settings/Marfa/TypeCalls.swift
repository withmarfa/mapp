import Foundation

// What the Types page asks of the server, in values of its own. A type is read from `GET /types`, which answers only what each
// type declares, so a word or a field belongs to the type that declares it and a child reads the rest from its parents.

/// Where a type came from, as the server records it (`provenance.origin`).
nonisolated enum TypeOrigin: Hashable, Sendable {
    /// Marfa ships it.
    case platform
    /// The owner, or an app the owner allowed, registered it.
    case registered
    case plugin
    case unknown
}

/// The sign-in that first registered a type, as the server recorded it (`provenance.created_by`).
nonisolated struct TypeCreator: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case browser, app, key, local
    }

    var kind: Kind
    var id: String
    var name: String
}

/// One word a status field takes, in one of four groups.
nonisolated struct StatusWordRecord: Hashable, Sendable {
    var value: String
    var group: String
    var meaning: String?
}

/// A field a type declares itself.
nonisolated struct TypeFieldRecord: Hashable, Sendable {
    var key: String
    var label: String?
    /// The server's name for the field's kind, such as `string` or `status`.
    var kind: String
    var meaning: String?
    var isRequired: Bool
    var isSearchable: Bool
    var longest: Int?
    /// The words a choice field offers, in order.
    var choices: [String] = []
    var statusWords: [StatusWordRecord]
}

/// What a type says about how long its feed items stay, which a type that says nothing takes from the one above.
nonisolated enum FeedWindow: Hashable, Sendable {
    case days(Int)
    /// The type keeps its feed items although a type above expires them.
    case never
}

/// How long a type keeps its items' versions, where the type sets it.
nonisolated enum VersionWindow: Hashable, Sendable {
    /// Every version for this many days, then only each item's newest.
    case days(Int)
    /// Windows set another way, such as from the command line, which the page shows and does not change.
    case custom
}

/// The kinds of field an owner adds. Marfa has more (lists, status words, thumbnails); those come from a plugin or the
/// command line.
nonisolated enum FieldKind: String, CaseIterable, Hashable, Sendable {
    case text = "string"
    case number
    case wholeNumber = "integer"
    case yesOrNo = "boolean"
    case date
    case dateAndTime = "datetime"
    case link = "url"
    case email
    case choice = "enum"
}

/// A type as the server lists it: what it declares itself.
nonisolated struct TypeRecord: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var plural: String?
    var description: String?
    var guidance: String?
    var parent: String?
    var origin: TypeOrigin
    var plugin: PluginOrigin?
    /// The sign-in that first registered the type, when the server recorded one. It does not by itself say the type is the owner's.
    var creator: TypeCreator?
    /// The icon the type declares itself; a child with none shows its parent's.
    var icon: String?
    var fields: [String: TypeFieldRecord]
    /// The feed window the type declares itself.
    var feedWindow: FeedWindow?
    /// The strategy the type declares for a field it names no strategy for: `last_writer_wins` or `keep_both_copies`.
    var mergeStrategy: String?
    /// The version windows the type declares itself.
    var versionWindow: VersionWindow?

    struct PluginOrigin: Hashable, Sendable {
        var name: String
        var version: String
    }

    var title: String { plural ?? label }
}

/// Every type the server lists, and the title each plugin gives itself, by the plugin's name.
nonisolated struct TypeListing: Hashable, Sendable {
    var types: [TypeRecord]
    var pluginTitles: [String: String] = [:]
}

/// One type's guidance, as read for a type below it.
nonisolated struct TypeGuidanceRecord: Hashable, Sendable {
    var type: String
    var guidance: String
}

/// A type read on its own: its guidance and its ancestors', nearest first.
nonisolated struct TypeReading: Hashable, Sendable {
    var guidance: String?
    /// The plural the server shows the type by, made by its regular rule where the type declares none.
    var plural: String?
    var ancestors: [TypeGuidanceRecord]
}

/// A change to the type itself. A word's name is made from what was typed, and the server judges it.
nonisolated enum TypeEdit: Hashable, Sendable {
    case label(String)
    case plural(String)
    case description(String)
    /// An empty text removes the type's guidance.
    case guidance(String)
    /// Nil takes the type out from under its parent.
    case parent(String?)
    case addWord(group: String, value: String)
    case wordMeaning(value: String, text: String)
    case addField(NewFieldRecord)
    case field(key: String, TypeFieldChange)
    case removeField(key: String)
    /// Nil leaves the window to the type above.
    case feedWindow(FeedWindow?)
    /// Nil leaves the strategy to the type above.
    case mergeStrategy(String?)
    /// Keeps every version for this many days, then only each item's newest. Nil leaves the windows to the type above.
    case versionWindow(Int?)
}

/// A field the owner adds to a type.
nonisolated struct NewFieldRecord: Hashable, Sendable {
    var key: String
    var label: String
    var kind: FieldKind
    /// The words a choice field offers; empty for any other kind.
    var choices: [String] = []
    var isRequired = false
    var isSearchable = true
}

/// A type the owner makes, under `user.`.
nonisolated struct NewTypeRecord: Hashable, Sendable {
    var id: String
    var label: String
    /// Empty leaves it to the server, which makes one from the label.
    var plural: String
    var icon: String?
    /// Nil makes a type based on nothing.
    var parent: String?
}

/// A folder, view or webhook that names a type, as a move of its items reads it.
nonisolated struct TypeSettingRecord: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case folder, view, webhook }
    /// Why a move can't change a setting (`types/move-blocked`, `types/move-settings-authority`).
    enum Block: Hashable, Sendable {
        /// This sign-in may not change the setting.
        case notPermitted
        /// Its filter names the type in a way a move can't rewrite, or rewriting would make it too long.
        case filterTerm
        /// It places the two types in different folders.
        case placementConflict
        /// A webhook's type filter names a type with subtypes.
        case subtypes
        /// A reason this app doesn't know, in the server's words.
        case other(String)
    }

    var kind: Kind
    var id: String?
    /// Where the setting names the type, such as `query.types` or `type_filter`.
    var field: String = ""
    /// Why a move can't change it. Nil where a move changes it to name the new type.
    var blocked: Block?
}

/// What moving a type's items would do: the items it moves and the settings that name the type.
nonisolated struct TypeMovePreview: Hashable, Sendable {
    /// Nil where the server refused the move before counting them.
    var items: Int?
    /// The items it moves.
    var ids: [String] = []
    var settings: [TypeSettingRecord]
    /// Tables items hold rows in that the target type doesn't declare, which stop the move.
    var tables: [String] = []

    /// Whether a move would do what `other` said it would: the same items, settings and tables.
    func isSame(as other: TypeMovePreview) -> Bool {
        Set(ids) == Set(other.ids) && Set(settings) == Set(other.settings) && Set(tables) == Set(other.tables)
    }
}

/// How a move of a type's items ended.
nonisolated struct TypeMoveResult: Hashable, Sendable {
    /// Items the job moved.
    var moved: Int = 0
    /// Items the job tried and left unmoved. Items made while it ran are not among them.
    var failed: Int = 0
    /// Items still of the old type that the sign-in can see.
    var remaining: Int
    /// Whether items the sign-in can't see are still of the old type.
    var remainingHidden: Bool
    /// Why the move stopped or left the settings as they were, in the server's words.
    var problem: String?

    /// Whether every item moved: a move with any item left or failed is partial.
    var isDone: Bool { failed == 0 && remaining == 0 && !remainingHidden && problem == nil }
}

/// A change to one field a type declares itself.
nonisolated enum TypeFieldChange: Hashable, Sendable {
    case label(String)
    /// An empty meaning leaves it out.
    case meaning(String)
    case required(Bool)
    case searchable(Bool)
    /// Nil takes the limit away.
    case longest(Int?)
    /// A choice after the ones the field offers now; one it already offers is left as it is.
    case addChoice(String)
    /// Takes one choice out of the ones the field offers now, which can't be the last.
    case removeChoice(String)
}

/// Why a call about a type did not do what was asked.
nonisolated enum TypeFailure: Error, Hashable, Sendable {
    case owner(OwnerFailure)
    /// The server refused what was written, naming the field in its own path and giving its words.
    case invalid(field: String?, message: String)
    /// A plugin installed the type, so only a newer version of the plugin changes it.
    case pluginType
    /// The type is not as the page showed it.
    case changedOnServer
    /// The server refused because an app's sign-in would change the type's guidance, and this Marfa takes that only from
    /// the command line (`types/guidance-app-made`).
    case guidanceByApp
    /// The owner closed the sign-in the server asked for, so nothing was sent.
    case canceled
    /// Items, a folder, a view or a webhook still name the type (`types/delete-in-use`).
    case inUse(items: Int?, settings: Int)
    /// Types are based on it (`types/delete-subtypes`).
    case hasSubtypes([String])
    /// Settings name the type in a way a move can't change, or items hold rows in tables the target lacks
    /// (`type_move_blocked`), so nothing moved.
    case moveBlocked(settings: [TypeSettingRecord], tables: [String])
}

/// What the Types page asks of the server. Every call needs the server and is never queued.
nonisolated protocol TypeCalls: Sendable {
    func types() async throws(TypeFailure) -> TypeListing
    /// The type's guidance and its ancestors' (`GET /types/{id}`).
    func reading(of type: String) async throws(TypeFailure) -> TypeReading
    /// Reads the type's own definition again and sends it back with `edit` applied. The replacement keeps the other fields
    /// from that read (`PUT /types/{id}` replaces the whole definition and has no write precondition).
    func change(_ type: String, _ edit: TypeEdit) async throws(TypeFailure)
    /// Registers a `user.*` type with its plural and icon, below its parent or based on nothing (`POST /types`).
    func addType(_ type: NewTypeRecord) async throws(TypeFailure)
    /// Deletes a type of the owner's that no type is based on (`DELETE /types/{id}`). Unforced, a type an item or a setting
    /// uses is refused; forced, its items and settings stay as they are, naming a type that is gone (`types/delete-force`).
    func delete(_ type: String, force: Bool) async throws(TypeFailure)
    /// What moving every item of `type` to `target` would do, changing nothing (`POST /types/{id}/move`, `dry_run`).
    func previewMove(of type: String, to target: String) async throws(TypeFailure) -> TypeMovePreview
    /// Moves every item of `type` to `target` and waits for the server's job to end (`types/move`, `types/move-settings`).
    func move(_ type: String, to target: String) async throws(TypeFailure) -> TypeMoveResult
}

nonisolated extension FieldKind {
    /// A field's kind for people, from the server's name for it. Kinds the owner cannot add are named too.
    static func title(ofKind raw: String) -> String {
        switch raw {
        case "string": String(localized: "Text")
        case "number": String(localized: "Number")
        case "integer": String(localized: "Whole Number")
        case "boolean": String(localized: "Yes or No")
        case "date": String(localized: "Date")
        case "datetime": String(localized: "Date and Time")
        case "url": String(localized: "Link")
        case "email": String(localized: "Email")
        case "enum": String(localized: "Choice")
        case "array": String(localized: "List")
        case "object": String(localized: "Group")
        case "thumbnail": String(localized: "Thumbnail")
        case "status": String(localized: "Status")
        default: raw
        }
    }

    var title: String { Self.title(ofKind: rawValue) }
}
