import SwiftUI

/// The Search page: what this server leaves out of search, whether archived and Inbox items are searched, and how the
/// results are ordered and shown. The leave-out is MAPP's own setting for this server (`SearchLeaveOuts`); the rest are
/// the Mac's (`SearchOptions`). A search inside one place or list leaves nothing out, since the person chose that place.
struct SearchPage: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @AppStorage(SearchOptions.includesArchivedKey) private var includesArchived = SearchOptions.includesArchivedStandard
    @AppStorage(SearchOptions.includesInboxKey) private var includesInbox = SearchOptions.includesInboxStandard
    @AppStorage(SearchOptions.orderKey) private var order = SearchOptions.Order.standard
    @AppStorage(SearchOptions.showsSnippetsKey) private var showsSnippets = SearchOptions.showsSnippetsStandard

    var body: some View {
        SettingsPageColumn {
            leftOut
            include
            results
        }
        .accessibilityIdentifier("SearchPage")
    }

    // MARK: Left out

    private var leaveOut: SearchLeaveOut { libraries.searchLeaveOut }

    private func change(_ change: (inout SearchLeaveOut) -> Void) {
        libraries.searchLeaveOuts.update(libraries.libraryKey, change)
    }

    private var leftOut: some View {
        SettingsSection("Left Out of Search", line: "They still show in their own place, in views and in Favorites.") {
            if let library {
                ForEach(SearchLeaveOutList.entries(for: leaveOut, catalogue: library.catalogue, sources: library.sources)) { entry in
                    row(for: entry, library: library)
                }
                addMenu(in: library)
            }
        }
        .accessibilityIdentifier("SearchLeftOut")
    }

    @ViewBuilder private func row(for entry: SearchLeaveOutList.Entry, library: any ItemLibrary) -> some View {
        switch entry.kind {
        case .type(let type):
            SettingsRow(
                verbatim: entry.title, line: entry.isKnown ? typeLine(type, in: library.catalogue) : String(localized: "Unknown type, kept until you remove it."),
                lead: .mark(Image(typeGlyph: entry.icon))
            ) {
                SettingsMoreMenu { removal { change { $0.types.remove(type) } } }
            }
        case .subtype(_, let parent):
            SettingsRow(verbatim: entry.title, lead: .mark(Image(typeGlyph: entry.icon)), size: .compact) {
                SettingsValue(verbatim: String(localized: "Left out with \(library.catalogue.plural(for: parent))"))
            }
        case .source(let code):
            SettingsRow(
                verbatim: entry.title, line: sourceLine(entry),
                lead: .mark(entry.icon.map { Image(typeGlyph: $0) } ?? Image(systemName: SourceTile.fallbackSymbol))
            ) {
                SettingsMoreMenu { removal { change { $0.sources.remove(code) } } }
            }
        }
    }

    private func removal(_ action: @escaping () -> Void) -> some View {
        Button("Stop Leaving Out", action: action)
    }

    private func typeLine(_ type: TypeID, in catalogue: Catalogue) -> String {
        catalogue.descendants(of: type).isEmpty ? String(localized: "A type.") : String(localized: "A type, with those under it.")
    }

    private func sourceLine(_ entry: SearchLeaveOutList.Entry) -> String {
        guard entry.isKnown else { return String(localized: "Unknown source, kept until you remove it.") }
        guard let count = entry.count else { return String(localized: "A source.") }
        return String(localized: "A source. \(count.formatted()) items.")
    }

    private func addMenu(in library: any ItemLibrary) -> some View {
        let catalogue = library.catalogue
        let types = SearchLeaveOutList.typesToAdd(library.itemTypeCounts, leaveOut: leaveOut, catalogue: catalogue)
        let sources = SearchLeaveOutList.sourcesToAdd(library.sourceCounts, leaveOut: leaveOut)
        let fitting = { (addition: SearchLeaveOutList.Addition) in SearchLeaveOutList.fits(addition, in: leaveOut, catalogue: catalogue) }
        let crossesLimit = types.contains { !fitting(.type($0.id)) } || sources.contains { !fitting(.source($0.code)) }
        return SettingsAddMenu("Leave Out a Type or Source…") {
            if !types.isEmpty {
                Section("Types") {
                    ForEach(types) { type in
                        Button { change { $0.types.insert(type.id) } } label: { Text(verbatim: type.label) }
                            .disabled(!fitting(.type(type.id)))
                    }
                }
            }
            if !sources.isEmpty {
                Section("Sources") {
                    ForEach(sources) { source in
                        Button { change { $0.sources.insert(source.code) } } label: { Text(verbatim: source.name) }
                            .disabled(!fitting(.source(source.code)))
                    }
                }
            }
            if crossesLimit {
                Divider()
                Text("Leaving out more would make a search too long to run.")
            }
        }
        .disabled(types.isEmpty && sources.isEmpty)
        .accessibilityIdentifier("LeaveOutAdd")
    }

    // MARK: Include

    private var include: some View {
        SettingsSection("Include") {
            SettingsRow("Archived Items") {
                SettingsToggle(title: "Archived Items", isOn: $includesArchived).accessibilityIdentifier("SearchArchived")
            }
            SettingsRow("Inbox Items", line: "What isn’t filed yet.") {
                SettingsToggle(title: "Inbox Items", isOn: $includesInbox).accessibilityIdentifier("SearchInbox")
            }
        }
    }

    // MARK: Results

    private var results: some View {
        SettingsSection("Results") {
            SettingsRow("Order") {
                SettingsPopUp(title: "Order", selection: $order) {
                    ForEach(SearchOptions.Order.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("SearchOrder")
            }
            SettingsRow("Show Snippets", line: "The words that matched, under each result.") {
                SettingsToggle(title: "Show Snippets", isOn: $showsSnippets).accessibilityIdentifier("SearchSnippets")
            }
        }
    }
}
