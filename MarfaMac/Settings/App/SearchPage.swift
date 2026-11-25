import SwiftUI

/// The Search page: what this server leaves out of search, whether archived and Feed items are searched, and how the
/// results are ordered and shown. The leave-out is the app's own setting for this server (`SearchLeaveOuts`); the rest are
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

    /// What the add menu offers, with the names the list uses.
    private struct Offer {
        let types: [SearchLeaveOutList.TypeChoice]
        let sources: [SourceCount]
        let labels: [TypeID: String]
        let isDimmed: (SearchLeaveOutList.Addition) -> Bool
        /// Whether some of what is offered would make more conditions than a search holds.
        let atLimit: Bool
    }

    private func offer(in library: any ItemLibrary) -> Offer {
        let catalogue = library.catalogue
        let counts = library.itemTypeCounts
        let labels = SearchLeaveOutList.labels(offered: counts.map(\.id), leaveOut: leaveOut, catalogue: catalogue)
        let types = SearchLeaveOutList.typesToAdd(counts, leaveOut: leaveOut, catalogue: catalogue, labels: labels)
        let sources = SearchLeaveOutList.sourcesToAdd(library.sourceCounts, leaveOut: leaveOut)
        let leaveOut = leaveOut
        let isDimmed = { (addition: SearchLeaveOutList.Addition) in !SearchLeaveOutList.fits(addition, in: leaveOut, catalogue: catalogue) }
        let atLimit = types.contains { isDimmed(.type($0.id)) } || sources.contains { isDimmed(.source($0.code)) }
        return Offer(types: types, sources: sources, labels: labels, isDimmed: isDimmed, atLimit: atLimit)
    }

    private var leftOut: some View {
        let offer = library.map(offer(in:))
        return SettingsSection(
            "Left Out of Search", line: "They still show in their own place, in views and in Favorites.",
            footer: offer?.atLimit == true ? "Some can’t be left out as well: a search can skip only so much. Stop leaving one out to make room." : nil
        ) {
            if let library, let offer {
                ForEach(SearchLeaveOutList.entries(for: leaveOut, catalogue: library.catalogue, sources: library.sources, labels: offer.labels)) { entry in
                    row(for: entry, library: library, labels: offer.labels)
                }
                addMenu(offer)
            }
        }
        .accessibilityIdentifier("SearchLeftOut")
    }

    @ViewBuilder private func row(for entry: SearchLeaveOutList.Entry, library: any ItemLibrary, labels: [TypeID: String]) -> some View {
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
                SettingsValue(verbatim: String(localized: "Left out with \(labels[parent] ?? library.catalogue.plural(for: parent))"))
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

    private func addMenu(_ offer: Offer) -> some View {
        SettingsAddMenu("Leave Out a Type or Source…") {
            if !offer.types.isEmpty {
                Section("Types") {
                    ForEach(offer.types) { type in
                        Button { change { $0.types.insert(type.id) } } label: { Text(verbatim: type.title) }
                            .disabled(offer.isDimmed(.type(type.id)))
                    }
                }
            }
            if !offer.sources.isEmpty {
                Section("Sources") {
                    ForEach(offer.sources) { source in
                        Button { change { $0.sources.insert(source.code) } } label: { Text(verbatim: source.name) }
                            .disabled(offer.isDimmed(.source(source.code)))
                    }
                }
            }
        }
        .disabled(offer.types.isEmpty && offer.sources.isEmpty)
        .accessibilityIdentifier("LeaveOutAdd")
    }

    // MARK: Include

    private var include: some View {
        SettingsSection("Include") {
            SettingsRow("Archived Items") {
                SettingsToggle(title: "Archived Items", isOn: $includesArchived).accessibilityIdentifier("SearchArchived")
            }
            SettingsRow("Feed Items", line: "What your apps send.") {
                SettingsToggle(title: "Feed Items", isOn: $includesInbox).accessibilityIdentifier("SearchInbox")
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
