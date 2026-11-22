import Foundation
import Marfa

/// One of the item's fields, each a JSON object of the settings that come once, by the Settings page they are on. A
/// member is named by the defaults key MAPP keeps the setting under.
nonisolated enum PreferencesField: String, CaseIterable, Codable, Hashable, Sendable {
    case appearance, general, editor, lists, search
}

/// One of the item's tables, each with the same three columns (`PreferencesType.columns`).
nonisolated enum PreferencesTable: String, CaseIterable, Codable, Hashable, Sendable {
    case commands, types, views, places, sidebar
}

/// `app.mapp.preferences`: one hidden item per Marfa that holds MAPP's own settings, so every Mac that connects to the
/// Marfa uses them.
///
/// The type can never change shape. Every Mac is another OAuth client to the server, and only the one that registered
/// the first type under `app.mapp` may replace it (`types/app-vendor-claimed-refused`, withmarfa/marfa#3462), so a new
/// setting is a new member inside a field or a new `setting` word in a table, never a new field or column.
/// `PreferencesTypeTests` holds the definition fixed.
nonisolated enum PreferencesType {
    static let id = "app.mapp.preferences"

    /// The scope that reaches the item from a sign-in other than the one that registered the type.
    static let vendorScope = "app.mapp.*:write"
    /// The scopes that reach the item whoever holds the vendor.
    static let reachingScopes: Set<String> = [vendorScope, "app.*:write"]
    /// What registering the type needs, as the first Mac's hydration does.
    static let registeringScope = "metadata.types:write"

    static let fieldDescriptions: [PreferencesField: String] = [
        .appearance: "MAPP's Appearance settings, by the key MAPP keeps each under.",
        .general: "MAPP's General settings, by the key MAPP keeps each under.",
        .editor: "MAPP's Editor settings, by the key MAPP keeps each under.",
        .lists: "MAPP's Lists settings, by the key MAPP keeps each under.",
        .search: "MAPP's Search settings, by the key MAPP keeps each under.",
    ]

    static let tableDescriptions: [PreferencesTable: String] = [
        .commands: "A shortcut for each menu command, and the shortcuts that work in any app.",
        .types: "What each type's page shows, its look and whether its list includes its subtypes.",
        .views: "What MAPP shows of each saved view on every Mac.",
        .places: "The default view, density, tab and order of each place.",
        .sidebar: "The sidebar's tabs, sections, order, hidden places and colors.",
    ]

    /// The three columns every table has.
    static let columns: JSONObject = [
        "key": .object([
            "type": "string", "required": true,
            "description": "What the row is for: a command, a type, a view, a place or a part of the sidebar.",
        ]),
        "setting": .object([
            "type": "string", "required": true, "description": "Which of MAPP's settings the row holds.",
        ]),
        "value": .object(["type": "string", "description": "The setting's value, as the JSON text MAPP stores."]),
    ]

    /// The definition MAPP declares (`WorkingCopy.declareTypes`).
    static let definition: JSONObject = {
        var fields: [(String, JSONValue)] = []
        for field in PreferencesField.allCases {
            fields.append((field.rawValue, .object(["type": "object", "description": .string(fieldDescriptions[field] ?? "")])))
        }
        var tables: [(String, JSONValue)] = []
        for table in PreferencesTable.allCases {
            tables.append((table.rawValue, .object([
                "description": .string(tableDescriptions[table] ?? ""), "columns": .object(columns),
            ])))
        }
        return JSONObject([
            ("id", .string(id)), ("version", .integer(1)), ("label", "MAPP Settings"), ("plural", "MAPP Settings"),
            ("description", "MAPP's own settings for this Marfa, which every Mac that connects to it uses."),
            ("fields", .object(JSONObject(fields))), ("tables", .object(JSONObject(tables))),
        ])
    }()
}
