import SwiftUI

/// Group by, one menu for every layout but the timeline and the calendar, drawn alike in View Options, the View menu and
/// Edit View from the place's offer (`GroupOffer`). A choice a saved view cannot hold yet is shown dimmed there.
struct GroupByMenu: View {
    @CurrentLibrary private var library
    let browser: Browser

    var body: some View {
        Menu("Group by", systemImage: "rectangle.grid.1x2") {
            GroupByChoices(browser: browser, offer: browser.groupOffer(in: library), shown: browser.shownGrouping(in: library))
            Divider()
            GroupByExtras(browser: browser)
        }
        .accessibilityIdentifier("GroupBy")
    }
}

/// The choices of Group by: None, Status, the fields, what every item has, then More Fields.
struct GroupByChoices: View {
    let browser: Browser
    let offer: GroupOffer
    let shown: ItemTableOptions.Grouping

    var body: some View {
        if offer.offersNone {
            choice(String(localized: "None"), .none, isKept: true)
            Divider()
        }
        ForEach(Array(offer.sections.enumerated()), id: \.offset) { index, section in
            if index > 0 { Divider() }
            ForEach(section) { entry($0) }
        }
        if !offer.moreFields.isEmpty {
            Divider()
            Menu("More Fields") {
                ForEach(offer.moreFields) { entry($0) }
            }
        }
    }

    @ViewBuilder private func entry(_ entry: GroupOffer.Entry) -> some View {
        if entry.choices.count == 1, let only = entry.choices.first {
            choice(entry.label, only.grouping, isKept: only.isKept)
        } else {
            Menu(entry.label) {
                ForEach(entry.choices) { option in
                    if option.startsSection { Divider() }
                    choice(option.label, option.grouping, isKept: option.isKept)
                }
            }
        }
    }

    private func choice(_ label: String, _ grouping: ItemTableOptions.Grouping, isKept: Bool) -> some View {
        Toggle(isOn: Binding { shown == grouping } set: { _ in browser.chooseGrouping(grouping) }) {
            Text(verbatim: label)
        }
        .disabled(!isKept)
        .help(isKept ? "" : String(localized: "A saved view can’t keep this grouping yet."))
    }
}

/// Hide Empty Groups in every layout that groups, then Collapse All Groups and Expand All Groups where groups fold: the
/// list and the table.
struct GroupByExtras: View {
    @CurrentLibrary private var library
    let browser: Browser

    var body: some View {
        Toggle("Hide Empty Groups", isOn: Binding { browser.hidesEmptyGroups } set: { browser.setHidesEmptyGroups($0) })
            .accessibilityIdentifier("HideEmptyGroups")
        if browser.viewMode == .list || browser.viewMode == .table {
            let grouped = browser.shownGrouping(in: library) != .none && browser.datedList == nil
            Button("Collapse All Groups") { browser.collapseAllGroups(in: library) }
                .disabled(!grouped)
            Button("Expand All Groups") { browser.expandAllGroups() }
                .disabled(!grouped)
        }
    }
}

extension ViewOptionCommand {
    /// Group by's choices as palette commands: each one not already made that the place can keep, by its field and,
    /// under a field with several, its way ("Group by Due: Week"), then Ungroup.
    static func grouping(_ browser: Browser, _ library: any ItemLibrary) -> [ViewOptionCommand] {
        let offer = browser.groupOffer(in: library)
        let shown = browser.shownGrouping(in: library)
        var commands: [ViewOptionCommand] = []
        for entry in offer.entries {
            for choice in entry.choices where choice.isKept && choice.grouping != shown {
                // Each value of a field is the field itself; a field's other ways name the way.
                let title = choice.grouping.mode == .value
                    ? String(localized: "Group by \(entry.label)") : String(localized: "Group by \(entry.label): \(choice.label)")
                commands.append(.init(title: title, systemImage: "rectangle.grid.1x2", group: .sortAndGroup) {
                    browser.chooseGrouping(choice.grouping)
                })
            }
        }
        if offer.offersNone, shown != .none {
            commands.append(.init(title: String(localized: "Ungroup"), systemImage: "rectangle.grid.1x2", group: .sortAndGroup) {
                browser.chooseGrouping(.none)
            })
        }
        return commands
    }
}
