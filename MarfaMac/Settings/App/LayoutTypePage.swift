import SwiftUI

/// One type's Layouts page: how its items read in a row, which facts follow the status, and what its page pins under the
/// title. Every change is written to the stores that already hold it, the type's look (`TypeLooks`) and what its page
/// shows (`PagePlacements`, the same store as a row's menu on an item's page), which sync through the Marfa (`PreferencesSync`).
struct LayoutTypePage: View {
    let type: TypeID
    let placements: PagePlacements
    let defaults: UserDefaults
    let typeLooks: TypeLooks
    let key: String
    let library: any ItemLibrary
    @Environment(\.settingsNavigation) private var navigation
    @Environment(\.colorScheme) private var scheme

    private var catalogue: Catalogue { library.catalogue }
    private var info: ItemTypeInfo? { catalogue.itemTypes[type] }
    private var choices: LayoutChoices { LayoutChoices(type: type, catalogue: catalogue) }
    private var look: TypeLook { typeLooks.looks(in: catalogue, library: key)[type] ?? .empty }
    var hasChanges: Bool { typeLooks.hasChoice(for: type, in: key) || placements.hasChoice(for: type) }

    var body: some View {
        SettingsPageColumn {
            head
            preview
            row
            facts
            page
            SettingsBar(edge: .leading) {
                SettingsButton("Restore Defaults") { restore() }
                    .disabled(!hasChanges)
                    .accessibilityIdentifier("RestoreLayout")
            }
        }
        .accessibilityIdentifier("LayoutTypePage")
    }

    // MARK: Head and preview

    private var head: some View {
        let preset = LookPreset.suggested(for: type, in: catalogue)
        let changes = typeLooks.changeCount(for: type, in: key) + (placements.hasChoice(for: type) ? 1 : 0)
        return SettingsHead(
            lead: TypeTile(icon: info?.icon, size: .large),
            title: Text(verbatim: info?.plural ?? type.rawValue),
            line: Text(verbatim: Self.startsAs(preset.startsAs, changes: changes))
        ) {
            SettingsButton("Show in Types") {
                navigation?.show(.types, subpage: SettingsSubpage(id: "type:" + type.rawValue, title: info?.plural ?? type.rawValue))
            }
            .accessibilityIdentifier("ShowInTypes")
        }
    }

    private static func startsAs(_ words: String, changes: Int) -> String {
        switch changes {
        case 0: String(localized: "Starts \(words.lowercased()).")
        case 1: String(localized: "Starts \(words.lowercased()). One place changed.")
        default: String(localized: "Starts \(words.lowercased()). \(changes) places changed.")
        }
    }

    @ViewBuilder private var preview: some View {
        let items = library.items(in: .type(type)).prefix(2)
        if !items.isEmpty {
            let list = RowList(date: .look, format: DateFormat.stored(), day: Calendar.current.startOfDay(for: library.now()))
            SettingsSection("Preview") {
                SettingsPreview {
                    ForEach(items) { item in
                        ItemRow(
                            content: RowContent.make(
                                for: item, look: look, catalogue: catalogue, list: list,
                                relations: library.relations(of: item, wanting: look.relations, counts: look.counts)))
                    }
                }
            }
        }
    }

    // MARK: Row

    private var row: some View {
        SettingsSection("Row") {
            SettingsRow("Date", line: "Top right.") {
                SettingsPopUp(title: "Date", selection: Binding { look.date } set: { date in change { $0.date = date } }) {
                    ForEach(choices.dates, id: \.self) { Text(verbatim: choices.title(of: $0)).tag($0) }
                }
                .accessibilityIdentifier("LayoutDate")
            }
            SettingsRow("Secondary line", line: "Under the title. Up to two.") {
                SettingsMultiPopUp(
                    title: "Secondary Line",
                    options: choices.parts.map { SettingsListEntry(id: $0.word, title: choices.title(of: $0)) },
                    selection: Binding { look.secondary.map(\.word) } set: { words in
                        change { $0.secondary = words.compactMap { LookPart(word: $0) } }
                    },
                    emptyTitle: "Nothing")
                    .accessibilityIdentifier("LayoutSecondary")
            }
            color
        }
    }

    /// The color of the type's mark, which comes from its icon (`TypeTone`), so it is read here and chosen there.
    private var color: some View {
        let tone = TypeTone(icon: info?.icon)
        return SettingsRow("Color", line: "\(tone.title) comes from its symbol.") {
            Circle()
                .fill(tone.color(for: scheme))
                .frame(width: SettingsTokens.Metric.swatch, height: SettingsTokens.Metric.swatch)
                .accessibilityLabel(tone.title)
        }
        .accessibilityIdentifier("LayoutColor")
    }

    // MARK: Facts

    private var facts: some View {
        let shown = look.facts
        return SettingsSection("Facts", line: "After the status, in this order. A row shows the first two.") {
            SettingsOrderedList(
                entries: Binding {
                    shown.map { SettingsListEntry(id: $0.word, title: choices.title(of: $0)) }
                } set: { entries in
                    change { $0.facts = entries.compactMap { LookFact(word: $0.id) } }
                },
                candidates: choices.facts.filter { !shown.contains($0) }.map { SettingsListEntry(id: $0.word, title: choices.title(of: $0)) },
                addTitle: "Add a Fact",
                onAdd: { added in
                    guard let fact = LookFact(word: added.id) else { return }
                    change { $0.facts.append(fact) }
                })
        }
        .accessibilityIdentifier("LayoutFacts")
    }

    // MARK: Page

    private var rows: [PageLayout.Row] {
        if let sample = library.items(in: .type(type)).first {
            return PageLayout.rows(
                of: sample, type: info, hidden: library.hiddenPropertyKeys(of: sample),
                relationships: library.relationships(for: sample.id), catalogue: catalogue,
                showsCoordinates: ShowsCoordinates.stored())
        }
        return PageLayout.rows(ofType: type, catalogue: catalogue)
    }

    private var page: some View {
        let rows = rows
        let pins = placements.pins(of: type, in: catalogue)
        let pinned = pins.compactMap { id in rows.first { $0.id == id } }
        return SettingsSection("Page", line: "Pinned under the title.") {
            SettingsOrderedList(
                entries: Binding {
                    pinned.map { SettingsListEntry(id: $0.id, title: $0.label) }
                } set: { entries in
                    PagePlacements.update(in: defaults) { current in
                        let missing = current.pins(of: type, in: catalogue).filter { id in !rows.contains { $0.id == id } }
                        current.setPins(entries.map(\.id) + missing, of: type)
                    }
                },
                candidates: rows.filter { $0.id != PagePlacement.linkedFrom && !pins.contains($0.id) }
                    .map { SettingsListEntry(id: $0.id, title: $0.label) },
                addTitle: "Pin a Property…",
                isFull: pins.count >= PagePlacement.pinLimit,
                onAdd: { added in pin(added.id) })
            SettingsRow("Linked from", line: "What links to an item of this type.") {
                SettingsPopUp(
                    title: "Linked From",
                    selection: Binding {
                        placements.placement(of: type, in: catalogue).linkedFromPlace
                    } set: { setLinkedFrom($0) }
                ) {
                    Text("At the Foot of the Page").tag(LinkedFromPlace.page)
                    Text("In the Panel").tag(LinkedFromPlace.inspector)
                }
                .accessibilityIdentifier("LayoutLinkedFrom")
            }
        }
        .accessibilityIdentifier("LayoutPage")
    }

    // MARK: Writing

    func pin(_ row: String) {
        PagePlacements.update(in: defaults) { $0.pin(row, of: type, in: catalogue) }
    }

    func setLinkedFrom(_ place: LinkedFromPlace) {
        PagePlacements.update(in: defaults) { $0.setLinkedFrom(place, of: type, in: catalogue) }
    }

    private func change(_ edit: (inout TypeLook) -> Void) {
        typeLooks.change(type, in: key, catalogue: catalogue, edit)
    }

    /// Takes back this type's choices and nothing else's: its look, and what its page shows.
    func restore() {
        typeLooks.restore(type, in: key)
        PagePlacements.update(in: defaults) { $0.reset(type) }
    }
}
