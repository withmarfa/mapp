import Marfa
import SwiftUI

/// Where a type's own page is among the Layouts sub-pages: one for each type, named by its identifier.
enum LayoutsSubpage {
    private static let prefix = "layout:"

    static func subpage(for type: TypeID, label: String) -> SettingsSubpage {
        SettingsSubpage(id: prefix + type.rawValue, title: label)
    }

    static func type(of subpage: SettingsSubpage?) -> TypeID? {
        guard let subpage, subpage.id.hasPrefix(prefix) else { return nil }
        return TypeID(String(subpage.id.dropFirst(prefix.count)))
    }
}

/// A type in the library catalogue can have a layout before it has any items.
struct LayoutsPage: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.settingsNavigation) private var navigation
    @Environment(\.settingsSubpage) private var subpage
    @Environment(\.library) private var library
    @State private var placements = PagePlacements()

    private var defaults: UserDefaults { libraries.preferences.defaults }

    var body: some View {
        Group {
            if let library, let subpage, let type = LayoutsSubpage.type(of: subpage) {
                if library.catalogue.itemTypes[type] != nil {
                    LayoutTypePage(type: type, placements: placements, defaults: defaults, typeLooks: libraries.typeLooks,
                                   key: libraries.libraryKey, library: library)
                } else if library.isLoaded {
                    SettingsPageState(
                        symbol: "rectangle.stack", title: Text(verbatim: MissingChoice.label(subpage.title)),
                        line: Text("This type is no longer in this library."), action: ("Back", { navigation?.back() }))
                } else {
                    ProgressView()
                }
            } else if let library {
                LayoutsList(catalogue: library.catalogue, placements: placements)
            } else {
                SettingsPageState(
                    symbol: "rectangle.stack", title: Text("No Library Open"),
                    line: Text("Layouts are shown once a Marfa is connected."))
            }
        }
        .onAppear { placements = PagePlacements.stored(in: defaults) }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)) { _ in
            placements = PagePlacements.stored(in: defaults)
        }
        .accessibilityIdentifier("LayoutsPage")
    }
}

private struct LayoutsList: View {
    let catalogue: Catalogue
    let placements: PagePlacements
    @Environment(Libraries.self) private var libraries
    @Environment(\.settingsNavigation) private var navigation

    var body: some View {
        let types = catalogue.itemTypes.values.sorted {
            let order = $0.plural.localizedStandardCompare($1.plural)
            return order == .orderedSame ? $0.id.rawValue < $1.id.rawValue : order == .orderedAscending
        }
        let groups = Dictionary(grouping: types, by: LayoutsGroup.init)
        return SettingsPageColumn {
            if let yours = groups[.yours] {
                SettingsSection("Yours", footer: "How each type shows in rows, on cards and on its own page.") {
                    ForEach(yours) { row($0, describesLayout: true) }
                }
            }
            if let builtIn = groups[.builtIn] {
                SettingsSection("Built In") { ForEach(builtIn) { row($0) } }
            }
            if let plugins = groups[.plugins] {
                SettingsSection("From Plugins") { ForEach(plugins) { row($0) } }
            }
            if let registered = groups[.registered] {
                SettingsSection("Registered Types") { ForEach(registered) { row($0) } }
            }
            SettingsBar {
                SettingsButton("Export…", small: true) { LooksFiles.export(from: libraries) }.accessibilityIdentifier("ExportLayouts")
                SettingsButton("Import…", small: true) { LooksFiles.importLooks(into: libraries) }.accessibilityIdentifier("ImportLayouts")
            }
        }
    }

    private func row(_ type: ItemTypeInfo, describesLayout: Bool = false) -> some View {
        let line = describesLayout ? LayoutsListWords.line(
            startsAs: LookPreset.suggested(for: type.id, in: catalogue).startsAs, changes: changeCount(of: type.id)) : nil
        return SettingsLinkRow(verbatim: type.plural, line: line, lead: .custom(AnyView(TypeTile(icon: type.icon))), lines: nil) {
            navigation?.push(LayoutsSubpage.subpage(for: type.id, label: type.plural))
        }
        .accessibilityIdentifier("Layout-\(type.id.rawValue)")
    }

    /// What was changed for the type: a place of its look, or its page, each counted once.
    private func changeCount(of type: TypeID) -> Int {
        libraries.typeLooks.changeCount(for: type, in: libraries.libraryKey)
            + (placements.hasChoice(for: type) ? 1 : 0)
    }
}

nonisolated enum LayoutsGroup: Hashable {
    case yours, builtIn, plugins, registered

    init(_ type: ItemTypeInfo) {
        switch type.origin {
        case .platform, .unknown: self = .builtIn
        case .plugin: self = .plugins
        case .registered: self = type.id.rawValue.hasPrefix("user.") ? .yours : .registered
        }
    }
}

/// The line under a type on the Layouts list.
enum LayoutsListWords {
    static func line(startsAs: String, changes: Int) -> String {
        switch changes {
        case 0: String(localized: "\(startsAs).")
        case 1: String(localized: "\(startsAs), with one change.")
        default: String(localized: "\(startsAs), with \(changes) changes.")
        }
    }
}
