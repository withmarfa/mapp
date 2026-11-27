import SwiftUI

/// The Search page: what this server leaves out of search, whether archived and Feed items are searched, and how the
/// results are ordered and shown. The leave-out is the app's own setting for this server (`SearchLeaveOuts`); the rest are
/// the Mac's (`SearchOptions`). A search inside one place or list leaves nothing out, since the person chose that place.
struct SearchPage: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @AppStorage(SearchOptions.includesArchivedKey) private var includesArchived = SearchOptions.includesArchivedStandard
    @AppStorage(SearchOptions.includesFeedKey) private var includesFeed = SearchOptions.includesFeedStandard
    @AppStorage(SearchOptions.orderKey) private var order = SearchOptions.Order.standard
    @AppStorage(SearchOptions.showsSnippetsKey) private var showsSnippets = SearchOptions.showsSnippetsStandard
    @State private var namesByLibrary: [String: [String: String]] = [:]
    @State private var adding = false

    var body: some View {
        SettingsPageColumn {
            leftOut.id(libraries.libraryKey)
            include
            results
        }
        .settingsSheet(presenting: adding, dismiss: { adding = false }) {
            if let library {
                ExclusionSheet(library: library, libraries: libraries, libraryKey: libraries.libraryKey) { adding = false }
            }
        }
        .onChange(of: libraries.libraryKey) { adding = false }
        .accessibilityIdentifier("SearchPage")
    }

    // MARK: Left out

    private var leaveOut: SearchLeaveOut {
        var displayed = libraries.searchLeaveOut
        displayed.names.merge(namesByLibrary[libraries.libraryKey] ?? [:]) { _, lastSeen in lastSeen }
        return displayed
    }

    private func change(_ change: (inout SearchLeaveOut) -> Void) {
        libraries.searchLeaveOuts.update(libraries.libraryKey, change)
    }

    /// What the Add sheet offers, with the names the list uses.
    fileprivate struct Offer {
        let types: [SearchLeaveOutList.TypeChoice]
        let sources: [SourceCount]
        let labels: [TypeID: String]
        let isDimmed: (SearchLeaveOutList.Addition) -> Bool
        /// Whether some of what is offered would make more conditions than a search holds.
        let atLimit: Bool
    }

    fileprivate static func offer(in library: any ItemLibrary, leaveOut: SearchLeaveOut) -> Offer {
        let catalogue = library.catalogue
        let counts = library.itemTypeCounts
        let labels = SearchLeaveOutList.labels(offered: counts.map(\.id), leaveOut: leaveOut, catalogue: catalogue)
        let types = SearchLeaveOutList.typesToAdd(counts, leaveOut: leaveOut, catalogue: catalogue, labels: labels)
        let sources = SearchLeaveOutList.sourcesToAdd(library.sourceCounts, leaveOut: leaveOut)
        let isDimmed = { (addition: SearchLeaveOutList.Addition) in !SearchLeaveOutList.fits(addition, in: leaveOut, catalogue: catalogue) }
        let atLimit = types.contains { isDimmed(.type($0.id)) } || sources.contains { isDimmed(.source($0.code)) }
        return Offer(types: types, sources: sources, labels: labels, isDimmed: isDimmed, atLimit: atLimit)
    }

    private var leftOut: some View {
        let offer = library.map { Self.offer(in: $0, leaveOut: leaveOut) }
        return SettingsSection("Excluded", footer: "They still show in their own place.") {
            SettingsButton("Add…", small: true) { adding = true }
                .disabled(offer.map { $0.types.isEmpty && $0.sources.isEmpty } ?? true)
                .accessibilityIdentifier("LeaveOutAdd")
        } content: {
            if let library, let offer {
                ForEach(SearchLeaveOutList.entries(for: leaveOut, catalogue: library.catalogue, typesLoaded: library.isLoaded,
                                                   sources: library.sources, labels: offer.labels)) { entry in
                    row(for: entry, library: library, labels: offer.labels)
                }
            }
        }
        .accessibilityIdentifier("SearchLeftOut")
    }

    @ViewBuilder private func row(for entry: SearchLeaveOutList.Entry, library: any ItemLibrary, labels: [TypeID: String]) -> some View {
        switch entry.kind {
        case .type(let type):
            SettingsRow(
                verbatim: entry.isKnown ? entry.title : MissingChoice.label(entry.title),
                line: typeLine(type, in: library), lead: .custom(AnyView(TypeTile(icon: entry.icon))), lines: nil
            ) {
                removeMenu(.type(type))
            }
            .onChange(of: library.catalogue.itemTypes[type].map { _ in entry.title }, initial: true) { _, title in
                if let title { namesByLibrary[libraries.libraryKey, default: [:]][entry.id] = title }
            }
        case .subtype(_, let parent):
            SettingsRow(verbatim: entry.title, lead: .mark(Image(typeGlyph: entry.icon)), size: .compact) {
                SettingsValue(verbatim: String(localized: "Left out with \(labels[parent] ?? library.catalogue.plural(for: parent))"))
            }
        case .source(let code):
            SettingsRow(
                verbatim: entry.isKnown ? entry.title : MissingChoice.label(entry.title), line: sourceLine(entry),
                lead: .mark(entry.icon.map { Image(typeGlyph: $0) } ?? Image(systemName: SourceTile.fallbackSymbol)), lines: nil
            ) {
                removeMenu(.source(code))
            }
            .onChange(of: library.sources.infos[code]?.name, initial: true) { _, name in
                if let name { namesByLibrary[libraries.libraryKey, default: [:]][entry.id] = name }
            }
        }
    }

    private func removeMenu(_ addition: SearchLeaveOutList.Addition) -> some View {
        SettingsMoreMenu { Button("Remove") { change { $0.remove(addition) } } }
    }

    private func typeLine(_ type: TypeID, in library: any ItemLibrary) -> String {
        if !library.catalogue.descendants(of: type).isEmpty { return String(localized: "A type, with those under it.") }
        if let count = library.itemTypeCounts.first(where: { $0.id == type })?.count {
            if count == 1 { return String(localized: "A type. 1 item.") }
            return String(localized: "A type. \(count.formatted()) items.")
        }
        return String(localized: "A type.")
    }

    private func sourceLine(_ entry: SearchLeaveOutList.Entry) -> String {
        guard let count = entry.count else { return String(localized: "A source.") }
        if count == 1 { return String(localized: "A source. 1 item.") }
        return String(localized: "A source. \(count.formatted()) items.")
    }

    // MARK: Include

    private var include: some View {
        SettingsSection("Included") {
            SettingsRow("Archived items") {
                SettingsToggle(title: "Archived items", isOn: $includesArchived).accessibilityIdentifier("SearchArchived")
            }
            SettingsRow("Feed items", line: "What your apps send.") {
                SettingsToggle(title: "Feed items", isOn: $includesFeed).accessibilityIdentifier("SearchFeed")
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
            SettingsRow("Show matched words under each result", lines: nil) {
                SettingsToggle(title: "Show matched words under each result", isOn: $showsSnippets).accessibilityIdentifier("SearchSnippets")
            }
        }
    }
}

private struct ExclusionSheet: View {
    typealias Addition = SearchLeaveOutList.Addition

    let library: any ItemLibrary
    let libraries: Libraries
    let libraryKey: String
    let dismiss: () -> Void
    @State private var selection: Addition?

    var body: some View {
        let offer = SearchPage.offer(in: library, leaveOut: libraries.searchLeaveOuts.leaveOut(for: libraryKey))
        let name = selectedName(in: offer)
        return SettingsSheet(title: Text("Exclude from Search")) {
            VStack(alignment: .leading, spacing: SettingsTokens.Metric.sectionGap) {
                SettingsRow("Type or source") {
                    SettingsPopUp(title: "Type or source", selection: $selection) {
                        Text("Choose…").tag(nil as Addition?)
                        Section("Types") {
                            ForEach(offer.types) { type in
                                Text(verbatim: type.title).tag(Addition.type(type.id)).disabled(offer.isDimmed(.type(type.id)))
                            }
                        }
                        Section("Sources") {
                            ForEach(offer.sources) { source in
                                Text(verbatim: source.name).tag(Addition.source(source.code)).disabled(offer.isDimmed(.source(source.code)))
                            }
                        }
                    }
                }
                if offer.atLimit {
                    SettingsNote("A search can have up to ten conditions. Remove an exclusion to make room.")
                }
            }
        } buttons: {
            SettingsButton("Cancel", action: dismiss)
            SettingsButton("Add", role: .confirm) {
                guard let selection, libraryKey == libraries.libraryKey,
                      let name = selectedName(in: SearchPage.offer(in: library, leaveOut: libraries.searchLeaveOut)) else { return }
                libraries.searchLeaveOuts.update(libraryKey) { exclusions in
                    exclusions.exclude(selection, named: name)
                }
                dismiss()
            }
            .disabled(name == nil)
        }
    }

    private func selectedName(in offer: SearchPage.Offer) -> String? {
        guard let selection, !offer.isDimmed(selection) else { return nil }
        switch selection {
        case .type(let type): return offer.types.first { $0.id == type }?.label
        case .source(let code): return offer.sources.first { $0.code == code }?.name
        }
    }
}
