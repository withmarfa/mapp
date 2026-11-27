import Foundation
import Observation

nonisolated enum PreferenceGroup: String, CaseIterable, Codable, Sendable {
    case general, appearance, keyboard, editor, lists, layouts, search, viewsAndPlaces, sidebar

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .appearance: String(localized: "Appearance")
        case .keyboard: String(localized: "Keyboard shortcuts")
        case .editor: String(localized: "Editor")
        case .lists: String(localized: "Lists")
        case .layouts: String(localized: "Layouts")
        case .search: String(localized: "Search")
        case .viewsAndPlaces: String(localized: "Views and places")
        case .sidebar: String(localized: "Sidebar")
        }
    }

    init(_ field: PreferencesField) {
        switch field {
        case .general: self = .general
        case .appearance: self = .appearance
        case .editor: self = .editor
        case .lists: self = .lists
        case .search: self = .search
        }
    }

    init?(_ table: PreferencesTable, setting: String) {
        switch table {
        case .commands where setting == "shortcut": self = .keyboard
        case .commands: return nil
        case .types: self = .layouts
        case .views, .places: self = .viewsAndPlaces
        case .sidebar: self = .sidebar
        }
    }
}

nonisolated extension PreferenceUnit {
    var group: PreferenceGroup? {
        switch self {
        case .member(let field, _): PreferenceGroup(field)
        case .row(let table, let setting, _): PreferenceGroup(table, setting: setting)
        }
    }
}

nonisolated extension Set where Element == PreferenceGroup {
    func includes(_ group: PreferenceGroup?) -> Bool {
        group.map(contains) ?? false
    }

    func excludingFrom(_ units: PreferenceUnits) -> PreferenceUnits {
        isEmpty ? units : units.filter { !includes($0.key.group) }
    }
}

nonisolated extension SyncedSetting {
    var group: PreferenceGroup? {
        switch place {
        case .member(let field), .serverMember(let field, _): PreferenceGroup(field)
        case .rows(let table, let setting, _, _, _, _), .serverRows(let table, let setting, _), .set(let table, let setting):
            PreferenceGroup(table, setting: setting)
        case .sidebar: .sidebar
        }
    }
}

/// Every group syncs until the person turns it off on this Mac for this instance.
@Observable @MainActor final class PreferenceGroups {
    static let key = "preferencesGroupsOff"
    private let defaults: UserDefaults
    private var choices: [String: [String]]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        choices = defaults.dictionary(forKey: Self.key) as? [String: [String]] ?? [:]
    }

    func off(in instance: String) -> Set<PreferenceGroup> {
        Set((choices[instance] ?? []).compactMap(PreferenceGroup.init(rawValue:)))
    }

    func isOn(_ group: PreferenceGroup, in instance: String) -> Bool {
        !off(in: instance).contains(group)
    }

    func set(_ on: Bool, for group: PreferenceGroup, in instance: String) {
        var off = Set(choices[instance] ?? [])
        if on { off.remove(group.rawValue) } else { off.insert(group.rawValue) }
        choices[instance] = off.isEmpty ? nil : off.sorted()
        if choices.isEmpty { defaults.removeObject(forKey: Self.key) } else { defaults.set(choices, forKey: Self.key) }
    }

    func reset() { choices = [:] }
}
