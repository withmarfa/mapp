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
    var statusWords: [StatusWordRecord]
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
    /// The icon the type declares itself; a child with none shows its parent's.
    var icon: String?
    var fields: [String: TypeFieldRecord]

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
    var ancestors: [TypeGuidanceRecord]
}

/// A change to the type itself. A word's name is made from what was typed, and the server judges it.
nonisolated enum TypeEdit: Hashable, Sendable {
    case label(String)
    case plural(String)
    case description(String)
    /// Nil takes the type out from under its parent.
    case parent(String?)
    case addWord(group: String, value: String)
    case wordMeaning(value: String, text: String)
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
    /// The server refused because an app's sign-in would change the type's guidance, which only the owner writes
    /// (`types/guidance-app-made`).
    case guidanceByApp
}

/// What the Types page asks of the server. Every call needs the server and is never queued.
nonisolated protocol TypeCalls: Sendable {
    func types() async throws(TypeFailure) -> TypeListing
    /// The type's guidance and its ancestors' (`GET /types/{id}`).
    func reading(of type: String) async throws(TypeFailure) -> TypeReading
    /// Reads the type's own definition again and sends it back with `edit` made, so what another app changed meanwhile is
    /// kept (`PUT /types/{id}` replaces the whole definition and has no version).
    func change(_ type: String, _ edit: TypeEdit) async throws(TypeFailure)
    /// Registers `id`, a `user.*` type, below `parent` (`POST /types`).
    func addChild(id: String, label: String, below parent: String) async throws(TypeFailure)
}
