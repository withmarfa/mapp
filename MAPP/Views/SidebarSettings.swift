import SwiftUI

/// The Sidebar page of Settings: every place the open library's sidebar can show, each with a switch to show or
/// hide it, in the order the sidebar uses. A row moves within its group by dragging, by Move Up and Move Down in
/// its context menu, or by the same two accessibility actions. The choices belong to the library that is open, so
/// each library keeps its own sidebar.
struct SidebarSettings: View {
    @Environment(Libraries.self) private var libraries
    @Environment(\.library) private var library

    var body: some View {
        if let library {
            content(library, plan: SidebarPlan(library, layout: libraries.sidebarLayout))
        } else {
            ContentUnavailableView(
                "No Library Is Open", systemImage: "sidebar.left",
                description: Text("Open a library to choose what its sidebar shows."))
        }
    }

    private func content(_ library: any ItemLibrary, plan: SidebarPlan) -> some View {
        let topTypes = plan.types.map { SidebarPlace.type($0.id) }
        return Form {
            Section("Places") {
                group(plan.top, in: library, plan: plan)
            }
            Section("Browse") {
                group(plan.browse, in: library, plan: plan)
            }
            if plan.library.contains(.types) {
                Section {
                    row(.types, title: String(localized: "Show Types"), in: library, plan: plan, among: [])
                    ForEach(plan.types) { node in
                        row(.type(node.id), in: library, plan: plan, among: topTypes)
                            .disabled(plan.layout.isHidden(.types))
                        typeChildren(node, in: library, plan: plan, depth: 1)
                    }
                    .onMove { source, destination in
                        libraries.updateSidebarLayout { $0.move(topTypes, fromOffsets: source, toOffset: destination) }
                    }
                } header: {
                    Text("Types")
                } footer: {
                    Text("New types appear here automatically.")
                }
            }
            if plan.library.contains(.views) {
                Section("Views") {
                    row(.views, title: String(localized: "Show Views"), in: library, plan: plan, among: [])
                    let places = plan.views.map { SidebarPlace.view($0.id) }
                    ForEach(plan.views) { view in
                        row(.view(view.id), in: library, plan: plan, among: places)
                            .disabled(plan.layout.isHidden(.views))
                    }
                    .onMove { source, destination in
                        libraries.updateSidebarLayout { $0.move(places, fromOffsets: source, toOffset: destination) }
                    }
                }
            }
        }
        .settingsForm()
        .accessibilityIdentifier("SidebarSettings")
    }

    /// The rows under a type, indented, each with its switch; they keep the order of their items.
    private func typeChildren(_ node: TypeNode, in library: any ItemLibrary, plan: SidebarPlan, depth: Int) -> AnyView {
        AnyView(ForEach(node.children) { child in
            row(.type(child.id), in: library, plan: plan, among: [], depth: depth)
                .disabled(plan.layout.isHidden(.types) || plan.layout.isHidden(.type(node.id)))
            typeChildren(child, in: library, plan: plan, depth: depth + 1)
        })
    }

    /// The rows of one group, which move among themselves.
    private func group(_ places: [SidebarPlace], in library: any ItemLibrary, plan: SidebarPlan, disabled: Bool = false) -> some View {
        ForEach(places, id: \.key) { place in
            row(place, in: library, plan: plan, among: places)
                .disabled(disabled)
        }
        .onMove { source, destination in
            libraries.updateSidebarLayout { $0.move(places, fromOffsets: source, toOffset: destination) }
        }
    }

    private func row(
        _ place: SidebarPlace, title: String? = nil, in library: any ItemLibrary, plan: SidebarPlan, among places: [SidebarPlace],
        depth: Int = 0
    ) -> some View {
        let index = places.firstIndex(of: place)
        let canMoveUp = index.map { $0 > 0 } ?? false
        let canMoveDown = index.map { $0 < places.count - 1 } ?? false
        return Toggle(isOn: Binding {
            plan.isShown(place)
        } set: { isShown in
            libraries.updateSidebarLayout { $0.setHidden(place, !isShown) }
        }) {
            Label {
                Text(title ?? self.title(place, in: library, plan: plan)).interfaceFont(.body)
            } icon: {
                Image(systemName: symbol(place, plan: plan)).interfaceFont(.body).foregroundStyle(.tint)
            }
            .padding(.leading, CGFloat(depth) * 20)
        }
        .toggleStyle(.switch)
        .contextMenu {
            if canMoveUp { Button("Move Up") { move(place, by: -1, among: places) } }
            if canMoveDown { Button("Move Down") { move(place, by: 1, among: places) } }
        }
        .accessibilityAction(named: "Move Up") { if canMoveUp { move(place, by: -1, among: places) } }
        .accessibilityAction(named: "Move Down") { if canMoveDown { move(place, by: 1, among: places) } }
        .accessibilityIdentifier("SidebarSetting-\(place.key)")
    }

    private func move(_ place: SidebarPlace, by offset: Int, among places: [SidebarPlace]) {
        guard let index = places.firstIndex(of: place) else { return }
        libraries.updateSidebarLayout {
            $0.move(places, fromOffsets: [index], toOffset: offset > 0 ? index + 2 : index - 1)
        }
    }

    private func title(_ place: SidebarPlace, in library: any ItemLibrary, plan: SidebarPlan) -> String {
        switch place {
        case .inbox: library.name(of: .inbox)
        case .recents: library.name(of: .recents)
        case .all: library.name(of: .allNotes)
        case .favorites: library.name(of: .favorites)
        case .sources: String(localized: "Sources")
        case .collections: String(localized: "Collections")
        case .types: String(localized: "Types")
        case .views: String(localized: "Views")
        case .files: library.name(of: .files)
        case .type(let id): Self.typeNode(id, in: plan.types)?.label ?? id
        case .view(let id): plan.views.first { $0.id == id }?.title ?? id.rawValue
        }
    }

    private func symbol(_ place: SidebarPlace, plan: SidebarPlan) -> String {
        switch place {
        case .inbox: "tray"
        case .recents: "clock"
        case .all: "note.text"
        case .favorites: "heart"
        case .sources: "antenna.radiowaves.left.and.right"
        case .collections: "square.stack"
        case .types: "square.grid.2x2"
        case .views: SidebarPlace.viewSymbol
        case .files: "doc"
        case .type(let id): Self.typeNode(id, in: plan.types)?.symbol ?? TypeSymbol.fallback
        case .view: SidebarPlace.viewSymbol
        }
    }

    private static func typeNode(_ id: String, in nodes: [TypeNode]) -> TypeNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = typeNode(id, in: node.children) { return found }
        }
        return nil
    }
}
