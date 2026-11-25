import SwiftUI

// MARK: What can be added

/// Something a place's menu can add: its key (a place's, or a type's identifier) and its name.
nonisolated struct SidebarPick: Equatable, Identifiable {
    let key: String
    let title: String

    var id: String { key }
}

/// What the faint places of Customize Sidebar and a heading's Add offer, worked out with the rest of the sidebar's
/// content.
nonisolated struct SidebarOffers: Equatable {
    /// Every saved view, and every collection, in the sidebar's order and by title.
    var views: [SidebarPick] = []
    var collections: [SidebarPick] = []
    /// The kinds a New command can make, by type identifier.
    var creatable: [SidebarPick] = []
    /// The types and kinds the person took out of the Types section.
    var hiddenTypes: [SidebarPick] = []
    /// The Library and the Feed where the person took them out.
    var hiddenPlaces: [SidebarPick] = []
    /// The Library's pages not under it.
    var pages: [SidebarPick] = []
    /// The built-in sections hidden, by kind, with their names.
    var hiddenSections: [SidebarGroup.Kind] = []
    /// The commands each tab holds, by the tab's identifier.
    var commands: [String: [SidebarShortcut]] = [:]

    @MainActor
    init(library: any ItemLibrary, plan: SidebarPlan, creatable: Set<String>) {
        let layout = plan.layout
        views = plan.views.map { SidebarPick(key: SidebarPlace.view($0.id).key, title: $0.title) }
        collections = library.collections.map { SidebarPick(key: SidebarPlace.collection($0.id).key, title: $0.displayTitle) }
        self.creatable = QuickAdd.types(in: library).filter { creatable.contains($0.id.rawValue) }
            .map { SidebarPick(key: $0.id.rawValue, title: $0.label) }
        func hidden(_ nodes: [TypeNode], under parent: String?) -> [SidebarPick] {
            nodes.flatMap { node in
                let title = parent.map { "\($0) › \(node.label)" } ?? node.label
                let own = layout.isHidden(.type(node.id)) ? [SidebarPick(key: SidebarPlace.type(node.id).key, title: title)] : []
                return own + hidden(node.children, under: title)
            }
        }
        hiddenTypes = hidden(plan.types, under: nil)
        hiddenPlaces = SidebarPlace.places.filter(layout.isHidden).compactMap { place in
            place.opens.map { SidebarPick(key: place.key, title: library.name(of: $0)) }
        }
        pages = SidebarPlace.pages.filter { layout.home(of: $0) == nil }.compactMap { place in
            place.opens.map { SidebarPick(key: place.key, title: library.name(of: $0)) }
        }
        hiddenSections = layout.allGroups.filter { [.pinned, .types].contains($0.kind) && layout.hides($0) }.map(\.kind)
        commands = Dictionary(grouping: layout.allGroups.filter { $0.kind == .shortcuts }, by: { layout.tabID(of: $0) })
            .mapValues { $0.flatMap(\.shortcuts) }
    }

    init() {}
}

// MARK: Places

/// A faint dashed place where something can be added while customizing: what the section can hold, a command, or a
/// section. It opens a menu of what can go there (`SidebarOfferMenu`).
struct SidebarAddPlace: View {
    /// The section it adds to; nil for the Section place, and for the Command place in a tab with no commands.
    let group: String?
    let kind: SidebarGroup.Kind
    let tab: String
    let offers: SidebarOffers
    let actions: SidebarActions
    /// The section's name, where it has one.
    var name: String?

    var body: some View {
        Menu {
            SidebarOfferMenu(group: group, kind: kind, tab: tab, offers: offers, actions: actions, name: name)
        } label: {
            SidebarDashedLabel(title: title, height: 28)
        }
        // A button style draws the label as it is; the borderless menu style drops its outline.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .selectionDisabled()
        .padding(.top, group == nil && kind == .custom ? 8 : 0)
        .accessibilityLabel(Text("Add \(title)"))
        .accessibilityIdentifier("SidebarAddPlace-\(group ?? kind.rawValue)")
    }

    private var title: String {
        switch kind {
        case .shortcuts: String(localized: "Command")
        case .places: String(localized: "Types, Collections, or Sources")
        case .pinned: String(localized: "View, Collection, or Item")
        case .types: String(localized: "Type")
        case .custom: group == nil ? String(localized: "Section") : String(localized: "View, Collection, or Item")
        }
    }
}

/// What a place, or a heading's Add, offers for its section.
struct SidebarOfferMenu: View {
    @Environment(Libraries.self) private var libraries
    let group: String?
    let kind: SidebarGroup.Kind
    let tab: String
    let offers: SidebarOffers
    let actions: SidebarActions

    /// The section's name, for the menu's heading: "Add to Pinned".
    var name: String?

    var body: some View {
        Section(heading) {
            switch kind {
            case .shortcuts: commands
            case .places: places
            case .pinned: pins(in: group ?? SidebarGroup.pinnedID)
            case .types: types
            case .custom:
                if let group { pins(in: group) } else { sections }
            }
        }
    }

    private var heading: String {
        switch kind {
        case .shortcuts: String(localized: "Add a Command")
        case .places: String(localized: "Add Under the Library")
        case .custom where group == nil: String(localized: "Add a Section")
        default: String(localized: "Add to \(name ?? SidebarGroup(id: "", kind: kind, tab: "").name)")
        }
    }

    @ViewBuilder private var commands: some View {
        let present = Set(offers.commands[tab] ?? [])
        let fixed: [(SidebarShortcut, String, String)] = [
            (.search, String(localized: "Search"), "magnifyingglass"), (.new, String(localized: "New"), "square.and.pencil"),
            (.settings, String(localized: "Settings"), "gearshape"),
        ]
        ForEach(fixed.filter { !present.contains($0.0) }, id: \.0.key) { shortcut, title, symbol in
            Button(title, systemImage: symbol) { add(shortcut) }
        }
        Menu("New Item") {
            ForEach(offers.creatable) { pick in
                let shortcut = SidebarShortcut.create(pick.key)
                Button(pick.title) { add(shortcut) }
                    .disabled(present.contains(shortcut))
            }
        }
        .disabled(offers.creatable.isEmpty)
    }

    private func add(_ shortcut: SidebarShortcut) {
        libraries.updateSidebarLayout { $0.addShortcut(shortcut, toTab: tab) }
    }

    @ViewBuilder private var places: some View {
        let group = group ?? SidebarGroup.placesID
        ForEach(offers.pages) { pick in
            Button(pick.title) {
                if let place = SidebarPlace(key: pick.key) { libraries.updateSidebarLayout { $0.put(place, in: group) } }
            }
        }
        if !offers.hiddenPlaces.isEmpty {
            Divider()
            ForEach(offers.hiddenPlaces) { pick in
                Button(pick.title) {
                    if let place = SidebarPlace(key: pick.key) { libraries.updateSidebarLayout { $0.setHidden(place, false) } }
                }
            }
        }
        if offers.pages.isEmpty, offers.hiddenPlaces.isEmpty {
            Button("All Pages Are Shown") {}.disabled(true)
        }
    }

    @ViewBuilder private func pins(in group: String) -> some View {
        Menu {
            ForEach(offers.views) { pick in
                Button(pick.title) {
                    if let place = SidebarPlace(key: pick.key) { libraries.updateSidebarLayout { $0.put(place, in: group) } }
                }
            }
        } label: {
            Label("View", systemImage: "tablecells")
        }
        .disabled(offers.views.isEmpty)
        Menu {
            ForEach(offers.collections) { pick in
                Button(pick.title) {
                    if let place = SidebarPlace(key: pick.key) { libraries.updateSidebarLayout { $0.put(place, in: group) } }
                }
            }
        } label: {
            Label("Collection", systemImage: "square.stack")
        }
        .disabled(offers.collections.isEmpty)
        Divider()
        Button("Item…", systemImage: "doc") { actions.chooseItem(group) }
    }

    @ViewBuilder private var types: some View {
        ForEach(offers.hiddenTypes) { pick in
            Button(pick.title) {
                if let place = SidebarPlace(key: pick.key) { libraries.updateSidebarLayout { $0.setHidden(place, false) } }
            }
        }
        if offers.hiddenTypes.isEmpty {
            Button("All Types Are Shown") {}.disabled(true)
        }
    }

    @ViewBuilder private var sections: some View {
        Button("New Section") { libraries.updateSidebarLayout { $0.addGroup(.custom, toTab: tab) } }
        if !offers.hiddenSections.isEmpty {
            Divider()
            ForEach(offers.hiddenSections, id: \.self) { kind in
                Button(SidebarGroup(id: kind.rawValue, kind: kind, tab: "").name) {
                    libraries.updateSidebarLayout { $0.addGroup(kind, toTab: tab) }
                }
            }
        }
    }
}

/// A faint dashed outline with a plus and what can be added, as Customize Sidebar draws its places.
struct SidebarDashedLabel: View {
    let title: String
    let height: CGFloat
    var capsule = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 10, weight: .medium))
            Text(title).lineLimit(1)
        }
        .interfaceFont(.subheadline)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 10)
        .frame(maxWidth: capsule ? nil : .infinity, minHeight: height, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: capsule ? height / 2 : 8, style: .continuous)
                .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }
        .contentShape(.rect)
    }
}

/// A dashed place that acts at once, as the Tab place does.
struct SidebarDashedButton: View {
    let title: String
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SidebarDashedLabel(title: title, height: height, capsule: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add \(title)"))
    }
}

// MARK: Choosing an item

/// Chooses the item that Item… pins: the items by title, the most recently edited first, narrowed by what is typed.
/// Return or a click chooses; Cancel or Escape chooses nothing.
struct SidebarItemChooser: View {
    @CurrentLibrary private var library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var highlighted = 0
    /// Read once, so typing in the field narrows a list that is already sorted.
    @State private var candidates: [Item] = []
    @State private var titles = PaletteMatch.Titles()
    let choose: (ItemID) -> Void

    private static let limit = 50

    private var matches: [Item] {
        titles.ranked(candidates.map(\.displayTitle), query).prefix(Self.limit).map { candidates[$0] }
    }

    var body: some View {
        let matches = matches
        VStack(alignment: .leading, spacing: 12) {
            Text("Pin an Item").interfaceFont(.title2.bold())
            InlineSearchField(
                text: $query, prompt: String(localized: "Search Items"), identifier: "SidebarItemField",
                onDown: { move(by: 1, count: matches.count) },
                onUp: { move(by: -1, count: matches.count) },
                onSubmit: { pick(matches, at: highlighted) },
                onCancel: { dismiss() })
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matches.indices, id: \.self) { index in
                            row(matches[index], isHighlighted: index == highlighted)
                                .id(index)
                                .onTapGesture { pick(matches, at: index) }
                        }
                    }
                }
                .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
            }
            .overlay {
                if matches.isEmpty { ContentUnavailableView.search(text: query) }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .appButton(.secondary)
            }
        }
        .padding(20)
        .frame(width: 440, height: 460)
        .onChange(of: query) { highlighted = 0 }
        .task { candidates = library.activeItems.sorted { $0.modified > $1.modified } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SidebarItemChooser")
    }

    private func row(_ item: Item, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            TonedGlyph(id: library.catalogue.icon(for: item.type))
            Text(item.displayTitle).lineLimit(1)
            Spacer(minLength: 8)
            Text(library.placeLabel(of: item)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 6, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }

    private func move(by step: Int, count: Int) {
        highlighted = min(max(highlighted + step, 0), max(count - 1, 0))
    }

    private func pick(_ matches: [Item], at index: Int) {
        guard matches.indices.contains(index) else { return }
        choose(matches[index].id)
        dismiss()
    }
}

// MARK: White

extension View {
    /// The sidebar in the color Settings › Appearance chose: the system's gray, or white behind a hairline. In dark
    /// the white sidebar takes the color a text view has there.
    @ViewBuilder func sidebarColor(_ color: SidebarColor) -> some View {
        switch color {
        case .gray: self
        case .white:
            scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor), ignoresSafeAreaEdges: .all)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(.separator).frame(width: 1).ignoresSafeArea()
                }
        }
    }
}
