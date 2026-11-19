import SwiftUI

/// The Sidebar page of Settings: the tabs, each tab's sections and the views with their colors, over the one layout
/// the sidebar reads (`SidebarLayout`), so it can do what customizing the sidebar in place does and no more. A change
/// applies at once and the sidebar follows; customizing in place while this page is open shows the same state.
/// `SidebarSettingsPlan` decides what each row says. A section moves by dragging, or with Move Up and Move Down in its
/// menu, which also renames it, moves it to another tab and, for a section of the person's own, removes it.
struct SidebarSettings: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @AppStorage(SidebarTypeRow.subtypeIconsKey) private var showsSubtypeIcons = false
    @State private var naming: SidebarNaming?
    @State private var name = ""

    var body: some View {
        if let library {
            content(SidebarSettingsPlan(library, layout: libraries.sidebarLayout))
        } else {
            ContentUnavailableView(
                "No Library Is Open", systemImage: "sidebar.left",
                description: Text("Open a library to choose what its sidebar shows."))
        }
    }

    private func content(_ plan: SidebarSettingsPlan) -> some View {
        let ask: (SidebarNaming) -> Void = { request in
            name = request.current
            naming = request
        }
        let tabs = plan.tabs.map(\.tab)
        return Form {
            Section {
                ForEach(plan.tabs) { tab in
                    SidebarTabSettingRow(tab: tab.tab, canRemove: tabs.count > 1, ask: ask)
                        .equatable()
                }
                SidebarAddRow(title: "Add Tab", identifier: "SidebarSettingsAddTab") { ask(.newTab(moving: nil)) }
            } header: {
                Text("Tabs")
            } footer: {
                if tabs.count == 1 { Text("With one tab, the sidebar shows no tab bar.") }
            }
            ForEach(plan.tabs) { tab in
                Section {
                    sections(of: tab, tabs: tabs, ask: ask)
                    SidebarAddSectionSettingRow(plan: plan, tab: tab.id)
                } header: {
                    Text(verbatim: tab.tab.name)
                }
            }
            Section {
                ForEach(plan.views) { row in
                    SidebarViewSettingRow(row: row)
                        .equatable()
                }
                .onMove { source, destination in
                    libraries.updateSidebarLayout { $0.moveViews(plan.views.map(\.place), fromOffsets: source, toOffset: destination) }
                }
            } header: {
                Text("Views")
            } footer: {
                Text("Saved views come from your Marfa server.")
            }
            if plan.hasTypes {
                Section {
                    Toggle("Show Icons on Subtypes", isOn: $showsSubtypeIcons)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("SidebarSubtypeIcons")
                } header: {
                    Text("Types")
                } footer: {
                    Text("The sidebar lists the first six types and keeps the rest under Show More. New types appear in the Types section automatically.")
                }
            }
        }
        .settingsForm()
        .namingAlert($naming, name: $name) { request, name in
            libraries.updateSidebarLayout { request.apply(name: name, to: &$0) }
        }
        .accessibilityIdentifier("SidebarSettingsPage")
    }

    @ViewBuilder private func sections(of tab: SidebarSettingsPlan.Tab, tabs: [SidebarTab], ask: @escaping (SidebarNaming) -> Void) -> some View {
        if tab.sections.isEmpty {
            Text("No sections in this tab.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("SidebarSettingsNoSections-\(tab.id)")
        } else {
            ForEach(Array(tab.sections.enumerated()), id: \.element.id) { index, section in
                SidebarSectionSettingRow(
                    section: section, tab: tab.id, tabs: tabs, position: index, count: tab.sections.count, ask: ask)
                    .equatable()
            }
            .onMove { source, destination in
                libraries.updateSidebarLayout { $0.moveGroups(inTab: tab.id, fromOffsets: source, toOffset: destination) }
            }
        }
    }
}

/// A row of a card: a mark, a title with an optional line under it, and the controls at the trailing edge.
private struct SidebarSettingRow<Mark: View, Controls: View>: View {
    let title: String
    var detail: String?
    var isDimmed = false
    @ViewBuilder let mark: Mark
    @ViewBuilder let controls: Controls

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                mark
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title).interfaceFont(.body).lineLimit(1)
                    if let detail {
                        Text(verbatim: detail).interfaceFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .opacity(isDimmed ? 0.5 : 1)
            Spacer(minLength: 8)
            controls
        }
        .contentShape(.rect)
    }
}

/// A tab: its mark and name and a Rename button. Remove Tab is in its menu, where there is more than one tab.
private struct SidebarTabSettingRow: View, Equatable {
    @Environment(Libraries.self) private var libraries
    let tab: SidebarTab
    let canRemove: Bool
    let ask: (SidebarNaming) -> Void

    static func == (a: Self, b: Self) -> Bool { a.tab == b.tab && a.canRemove == b.canRemove }

    var body: some View {
        SidebarSettingRow(title: tab.name) {
            Image(systemName: tab.symbol).interfaceFont(.body).foregroundStyle(.secondary)
        } controls: {
            Button("Rename…") { ask(.renameTab(tab.id, current: tab.name)) }
                .mappButton(.secondary, size: .small)
                .accessibilityIdentifier("SidebarSettingsRenameTab-\(tab.id)")
        }
        .contextMenu { actions }
        .accessibilityElement(children: .contain)
        .accessibilityActions { actions }
        .accessibilityIdentifier("SidebarSettingsTab-\(tab.id)")
    }

    @ViewBuilder private var actions: some View {
        Button("Rename…") { ask(.renameTab(tab.id, current: tab.name)) }
        Button("Remove Tab") { libraries.updateSidebarLayout { $0.removeTab(tab.id) } }
            .disabled(!canRemove)
    }
}

/// A row that adds something, in the place of a card where it will go.
private struct SidebarAddRow: View {
    let title: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
        }
        .mappButton(.plain, size: .small)
        .accessibilityIdentifier(identifier)
    }
}

/// A section of a tab: its mark, name and what it holds, a Show menu where it has rows to choose, and a switch that
/// hides it from the sidebar. A hidden section stays here, dimmed, so it can come back. A section of the person's own
/// has a Remove button in the switch's place, since hiding it removes it.
private struct SidebarSectionSettingRow: View, Equatable {
    @Environment(Libraries.self) private var libraries
    let section: SidebarSettingsPlan.Section
    let tab: String
    let tabs: [SidebarTab]
    let position: Int
    let count: Int
    let ask: (SidebarNaming) -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.section == b.section && a.tab == b.tab && a.tabs == b.tabs && a.position == b.position && a.count == b.count
    }

    var body: some View {
        SidebarSettingRow(title: section.title, detail: section.detail, isDimmed: !section.isShown) {
            Image(systemName: section.symbol).interfaceFont(.body).foregroundStyle(.secondary)
        } controls: {
            if !section.choices.isEmpty { showMenu }
            if section.canHide {
                Toggle(section.title, isOn: Binding {
                    section.isShown
                } set: { isShown in
                    libraries.updateSidebarLayout { isShown ? $0.showGroup(section.id) : $0.hideGroup(section.id) }
                })
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityIdentifier("SidebarSettingsSwitch-\(section.id)")
            } else {
                Button("Remove") { libraries.updateSidebarLayout { $0.hideGroup(section.id) } }
                    .mappButton(.secondary, size: .small)
                    .accessibilityIdentifier("SidebarSettingsRemove-\(section.id)")
            }
            SidebarHandle()
        }
        .contextMenu { actions }
        .accessibilityElement(children: .contain)
        .accessibilityActions { actions }
        .accessibilityIdentifier("SidebarSettingsSection-\(section.id)")
    }

    private var showMenu: some View {
        Menu {
            ForEach(section.choices) { choice in
                Toggle(choice.title, isOn: Binding {
                    choice.isShown
                } set: { isShown in
                    libraries.updateSidebarLayout { $0.setHidden(choice.place, !isShown) }
                })
            }
        } label: {
            Text("Show \(section.shownCount)")
        }
        .mappMenu(size: .small)
        .disabled(!section.isShown)
        .accessibilityLabel(Text("Show"))
        .accessibilityValue(Text("\(section.shownCount)"))
        .accessibilityIdentifier("SidebarSettingsShow-\(section.id)")
    }

    @ViewBuilder private var actions: some View {
        if section.canRename { Button("Rename…") { ask(.renameGroup(section.id, current: section.title)) } }
        Divider()
        Button("Move Up") {
            libraries.updateSidebarLayout { $0.moveGroups(inTab: tab, fromOffsets: [position], toOffset: position - 1) }
        }
        .disabled(position == 0)
        Button("Move Down") {
            libraries.updateSidebarLayout { $0.moveGroups(inTab: tab, fromOffsets: [position], toOffset: position + 2) }
        }
        .disabled(position >= count - 1)
        Menu("Move to Tab") {
            ForEach(tabs.filter { $0.id != tab }) { other in
                Button(other.name) { libraries.updateSidebarLayout { $0.moveGroup(section.id, toTab: other.id) } }
            }
            if tabs.count > 1 { Divider() }
            Button("New Tab…") { ask(.newTab(moving: section.id)) }
        }
        if section.canHide {
            Divider()
            Button(section.isShown ? "Hide Section" : "Show Section") {
                libraries.updateSidebarLayout { section.isShown ? $0.hideGroup(section.id) : $0.showGroup(section.id) }
            }
        }
    }
}

/// Add Section at the foot of a tab's card: a new section, alone or holding a collection or a source. A hidden built-in
/// section is a row of its own, switched off, so it is not offered here.
private struct SidebarAddSectionSettingRow: View {
    @Environment(Libraries.self) private var libraries
    let plan: SidebarSettingsPlan
    let tab: String

    var body: some View {
        Menu {
            Button("New Section") { libraries.updateSidebarLayout { $0.addGroup(.custom, toTab: tab) } }
            Divider()
            holding("A Collection", plan.unplacedCollections)
            holding("A Source", plan.unplacedSources)
        } label: {
            Label("Add Section", systemImage: "plus")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .mappButton(.plain, size: .small)
        .fixedSize()
        .accessibilityIdentifier("SidebarSettingsAddSection-\(tab)")
    }

    private func holding(_ title: LocalizedStringKey, _ picks: [SidebarPick]) -> some View {
        Menu(title) {
            ForEach(picks) { pick in
                Button(pick.title) {
                    libraries.updateSidebarLayout { layout in
                        let group = layout.addGroup(.custom, toTab: tab)
                        if let place = SidebarPlace(key: pick.key) { layout.put(place, in: group) }
                    }
                }
            }
        }
        .disabled(picks.isEmpty)
    }
}

/// A view: its mark in its color, a menu that chooses the color, and a switch. Dragging the row orders the views, as
/// Move Up and Move Down in its menu do.
private struct SidebarViewSettingRow: View, Equatable {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library
    @Environment(\.colorScheme) private var scheme
    let row: SidebarSettingsPlan.ViewRow

    static func == (a: Self, b: Self) -> Bool { a.row == b.row }

    var body: some View {
        SidebarSettingRow(title: row.title, isDimmed: !row.isShown || !row.isEnabled) {
            Image(systemName: row.symbol).interfaceFont(.body).foregroundStyle(row.tone.color(for: scheme))
        } controls: {
            Menu {
                SidebarColorPicker(place: row.place)
            } label: {
                Circle().fill(row.tone.color(for: scheme)).frame(width: 10, height: 10)
            }
            .mappMenu(size: .small)
            .disabled(!row.isEnabled)
            .accessibilityLabel(Text("Color"))
            .accessibilityValue(Text(row.tone.name))
            .accessibilityIdentifier("SidebarSettingsColor-\(row.place.key)")
            Toggle(row.title, isOn: Binding {
                row.isShown && row.isEnabled
            } set: { isShown in
                libraries.updateSidebarLayout { $0.setHidden(row.place, !isShown) }
            })
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!row.isEnabled)
            .accessibilityIdentifier("SidebarSetting-\(row.place.key)")
            SidebarHandle()
        }
        .contextMenu { actions }
        .accessibilityElement(children: .contain)
        .accessibilityActions { actions }
    }

    @ViewBuilder private var actions: some View {
        Button("Move Up") { move(by: -1) }.disabled(row.position == 0)
        Button("Move Down") { move(by: 1) }.disabled(row.position >= row.count - 1)
    }

    /// The views are read afresh, since the row holds only its own place.
    private func move(by offset: Int) {
        guard let library else { return }
        libraries.updateSidebarLayout { layout in
            let places = SidebarSettingsPlan(library, layout: layout).views.map(\.place)
            guard let index = places.firstIndex(of: row.place) else { return }
            layout.moveViews(places, fromOffsets: [index], toOffset: offset > 0 ? index + 2 : index - 1)
        }
    }
}
