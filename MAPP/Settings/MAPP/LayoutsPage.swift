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

/// The Layouts page: one row for each type of the server, which opens that type's own page. Nothing is left out, so a type
/// with no items yet is here too. Import and Export move every layout between Macs and servers as a file.
struct LayoutsPage: View {
    @Environment(\.settingsSubpage) private var subpage
    @Environment(\.library) private var library

    var body: some View {
        Group {
            if let type = LayoutsSubpage.type(of: subpage), library?.catalogue.itemTypes[type] != nil {
                LayoutTypePage(type: type)
            } else {
                LayoutsList()
            }
        }
        .accessibilityIdentifier("LayoutsPage")
    }
}

private struct LayoutsList: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @Environment(\.settingsPush) private var push
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()

    private var types: [ItemTypeInfo] {
        (library?.catalogue.itemTypes.values).map { Array($0) }?.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending } ?? []
    }

    var body: some View {
        if let library {
            list(of: library.catalogue)
        } else {
            SettingsPageState(
                symbol: "rectangle.stack", title: Text("No Library Open"),
                line: Text("Layouts are shown once a Marfa is connected."))
        }
    }

    private func list(of catalogue: Catalogue) -> some View {
        let own = types.filter { !$0.id.isShipped }
        let builtIn = types.filter { $0.id.isShipped }
        return SettingsPageColumn {
            if !own.isEmpty {
                SettingsSection("Your Types", line: "How each type shows in rows, on cards and on its own page.") {
                    ForEach(own) { row($0, in: catalogue) }
                }
            }
            SettingsSection("Built In", line: own.isEmpty ? "How each type shows in rows, on cards and on its own page." : nil) {
                ForEach(builtIn) { row($0, in: catalogue) }
            }
            SettingsBar {
                SettingsButton("Import…") { LooksFiles.importLooks(into: libraries) }.accessibilityIdentifier("ImportLayouts")
                SettingsButton("Export…") { LooksFiles.export(from: libraries) }.accessibilityIdentifier("ExportLayouts")
            }
        }
    }

    private func row(_ type: ItemTypeInfo, in catalogue: Catalogue) -> some View {
        let preset = LookPreset.suggested(for: type.id, in: catalogue)
        let changes = changeCount(of: type.id)
        return Button {
            push(LayoutsSubpage.subpage(for: type.id, label: type.plural))
        } label: {
            SettingsRow(
                verbatim: type.plural, line: LayoutsListWords.line(startsAs: preset.startsAs, changes: changes),
                lead: .custom(AnyView(TypeMark(icon: type.icon, size: .side)))
            ) { SettingsChevron() }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("Layout-\(type.id.rawValue)")
    }

    /// What was changed for the type: a place of its look, or its page, each counted once.
    private func changeCount(of type: TypeID) -> Int {
        libraries.typeLooks.changeCount(for: type, in: libraries.libraryKey)
            + (placements.hasChoice(for: type) ? 1 : 0)
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
