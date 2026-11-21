import Foundation
import Marfa

/// The words of the owner's pages: what an access scope, a permission and a refusal are called.
nonisolated enum OwnerWording {
    /// What a call that failed says in one line, under the row it was made from.
    static func line(_ failure: OwnerFailure) -> String {
        switch failure {
        case .unreachable: String(localized: "MAPP can’t reach the server. Nothing was changed.")
        case .signedOut: String(localized: "The server ended MAPP’s sign-in. Sign in again in Connection.")
        case .notPermitted(let scope): permissionLine(scope)
        case .notFound: String(localized: "It was removed somewhere else.")
        case .conflict: String(localized: "It changed somewhere else, so MAPP read it again. Nothing was changed.")
        case .instanceChanged: InstanceConfigFailure.anotherMarfaSentence
        case .notConfirmed: String(localized: "Nothing was changed: the sign-in wasn’t confirmed.")
        case .refused(let reason), .sourceHeld(let reason), .failed(let reason): reason
        }
    }

    /// One line naming what MAPP isn't allowed to do, from the permission the server named.
    static func permissionLine(_ scope: String?) -> String {
        guard let scope else { return String(localized: "MAPP isn’t allowed to do this.") }
        guard let permission = InstancePermission(rawValue: scope) else {
            return String(localized: "MAPP isn’t allowed to do this: it needs “\(scope)”.")
        }
        return String(localized: "MAPP isn’t allowed to \(permission.allowedTo).")
    }

    /// What a failure says on `page`: the page's own words where the server named the page's permission, otherwise the
    /// generic line.
    static func line(_ failure: OwnerFailure, on page: MarfaSettingsPage) -> String {
        if case .notPermitted(let scope) = failure { return permissionLine(scope, on: page) }
        return line(failure)
    }

    /// The line for a page that cannot be shown for want of the permission the server named: the page's own words when the
    /// server names the page's permission (or none), otherwise the generic line for the one it named.
    static func permissionLine(_ scope: String?, on page: MarfaSettingsPage) -> String {
        guard let permission = page.permission, scope == nil || scope == permission.rawValue else { return permissionLine(scope) }
        return page.permissionLine
    }

    /// How many of the owner's permissions a key, an app or a new key holds: "None", or "3 of 14".
    static func permissionCount(_ held: Int, of total: Int) -> String {
        held == 0 ? String(localized: "None") : String(localized: "\(held) of \(total)")
    }

    /// The title of an owner permission in a list of what an app or a key may do.
    static func title(of permission: String) -> String {
        switch InstancePermission(rawValue: permission) {
        case .auditRead?: String(localized: "Read the Audit Log")
        case .backupsManage?: String(localized: "Manage Backups")
        case .blobsManage?: String(localized: "Manage Files")
        case .configManage?: String(localized: "Change Settings")
        case .connectorsManage?: String(localized: "Manage Connectors")
        case .grantsManage?: String(localized: "Manage Apps")
        case .instanceMaintain?: String(localized: "Update and Maintain")
        case .instanceRead?: String(localized: "Read Server Status")
        case .itemsPurge?: String(localized: "Permanently Delete")
        case .keysManage?: String(localized: "Manage Keys")
        case .keysMint?: String(localized: "Make Keys")
        case .schemaWrite?: String(localized: "Change Types")
        case .signInsManage?: String(localized: "Manage Sign-Ins")
        case .webhooksManage?: String(localized: "Manage Webhooks")
        case nil: permission
        }
    }

    /// Each type's name by its id. Where several types share a label, one with a parent is told apart by the parent's label,
    /// "Task (Ticket)", as Search's list does; types still sharing a name after that keep their id in parentheses.
    static func typeNames(_ types: [(id: String, label: String, parent: String?)]) -> [String: String] {
        var labels: [String: String] = [:]
        var parents: [String: String] = [:]
        for type in types where labels[type.id] == nil {
            labels[type.id] = type.label
            parents[type.id] = type.parent
        }
        let shared = Set(Dictionary(grouping: labels, by: \.value).filter { $0.value.count > 1 }.keys)
        var names = labels
        for (id, label) in labels where shared.contains(label) {
            if let parent = parents[id], let parentLabel = labels[parent] { names[id] = "\(label) (\(parentLabel))" }
        }
        for (name, group) in Dictionary(grouping: names, by: \.value) where group.count > 1 {
            for (id, _) in group { names[id] = "\(name) (\(id))" }
        }
        return names
    }

    /// When something happened: today with the time, otherwise the day.
    static func when(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let date else { return nil }
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "yesterday")
        }
        let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if days > 0, days < 7 { return String(localized: "\(days) days ago") }
        return day(date, now: now, calendar: calendar)
    }

    /// A day as "3 October", with the year when it is not this one.
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.day().month(.wide)) : date.formatted(.dateTime.day().month(.wide).year())
    }

    /// "Used today", or "Never used".
    static func used(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let when = when(date, now: now, calendar: calendar) else { return String(localized: "Never used") }
        return String(localized: "Used \(when)")
    }
}

/// What a scope or a pattern of scopes reaches, in words, and the ways of narrowing it.
nonisolated enum AccessScopes {
    struct Entry: Hashable, Sendable, Identifiable {
        let pattern: String
        var level: AccessLevel
        var id: String { pattern }
    }

    struct Parsed: Hashable, Sendable {
        /// Each pattern with what it may do: the greater of what its scopes say.
        var entries: [Entry]
        /// The owner permissions among the scopes.
        var permissions: [String]
    }

    static func parse(_ scopes: [String]) -> Parsed {
        var order: [String] = []
        var levels: [String: AccessLevel] = [:]
        var permissions: [String] = []
        for scope in scopes {
            if InstancePermission(rawValue: scope) != nil {
                permissions.append(scope)
                continue
            }
            guard let colon = scope.lastIndex(of: ":") else { continue }
            let pattern = String(scope[..<colon])
            let level: AccessLevel
            switch scope[scope.index(after: colon)...] {
            case "read": level = .read
            case "write": level = .write
            default: continue
            }
            if levels[pattern] == nil { order.append(pattern) }
            levels[pattern] = max(levels[pattern] ?? .none, level)
        }
        return Parsed(entries: order.map { Entry(pattern: $0, level: levels[$0] ?? .none) }, permissions: permissions)
    }

    /// `scopes` with what `pattern` may do lowered to `level`, and nothing widened. What was written becomes a read where
    /// the grant held no read beside it, so Read Only never sends nothing for the pattern.
    static func narrowed(_ scopes: [String], pattern: String, to level: AccessLevel) -> [String] {
        let read = pattern + ":read"
        let write = pattern + ":write"
        let held: AccessLevel = scopes.contains(write) ? .write : scopes.contains(read) ? .read : .none
        guard level < held else { return scopes }
        var narrowed: [String] = []
        for scope in scopes {
            switch scope {
            case write:
                if level == .read, !scopes.contains(read) { narrowed.append(read) }
            case read:
                if level != .none { narrowed.append(scope) }
            default:
                narrowed.append(scope)
            }
        }
        return narrowed
    }

    static func removing(permission: String, from scopes: [String]) -> [String] {
        scopes.filter { $0 != permission }
    }

    /// What a pattern reaches, as a row's title. `names` is each type's label.
    static func title(of pattern: String, names: [String: String]) -> String {
        switch pattern {
        case "*": return String(localized: "All Data")
        case "content": return String(localized: "Your Content")
        case "edge.*": return String(localized: "All Links")
        case "metadata": return String(localized: "Types and Links")
        case "profile": return String(localized: "Your Profile")
        default: break
        }
        if let name = names[pattern] { return name }
        if pattern.hasPrefix("edge.") { return String(localized: "Links: \(pattern.dropFirst(5))") }
        if pattern.hasPrefix("metadata.") { return String(localized: "Definitions: \(pattern.dropFirst(9))") }
        if pattern.hasPrefix("profile.") { return String(localized: "Profile: \(pattern.dropFirst(8))") }
        if pattern.hasSuffix(".*") {
            let last = pattern.dropLast(2).split(separator: ".").last.map(String.init) ?? ""
            return String(localized: "\(last.prefix(1).uppercased() + last.dropFirst()) Types")
        }
        return pattern
    }

    /// One line of what the entries reach, for a list row.
    static func summary(_ parsed: Parsed, names: [String: String]) -> String {
        let reached = parsed.entries.filter { $0.level != .none }
        guard !reached.isEmpty else { return String(localized: "Reaches no items.") }
        let writes = reached.filter { $0.level == .write }.map { title(of: $0.pattern, names: names) }
        let reads = reached.filter { $0.level == .read }.map { title(of: $0.pattern, names: names) }
        var parts: [String] = []
        if !writes.isEmpty { parts.append(String(localized: "Reads and edits \(writes.formatted(.list(type: .and))).")) }
        if !reads.isEmpty { parts.append(String(localized: "Reads \(reads.formatted(.list(type: .and))).")) }
        return parts.joined(separator: " ")
    }
}
