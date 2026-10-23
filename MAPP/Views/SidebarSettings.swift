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
        let folderRows = plan.library.filter { $0 == .folders }
        let topTypes = plan.types.map { SidebarPlace.type($0.id) }
        return Form {
            Section("Places") {
                group(plan.top, in: library, plan: plan)
                row(.favorites, in: library, plan: plan, among: [])
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
            if !folderRows.isEmpty {
                Section("Folders") {
                    group(folderRows, in: library, plan: plan)
                }
            }
            if plan.library.contains(.collections) {
                Section {
                    row(.collections, title: String(localized: "Show Collections"), in: library, plan: plan, among: [])
                    ForEach(plan.collections) { node in
                        row(.collection(node.id), in: library, plan: plan, among: [])
                            .disabled(plan.layout.isHidden(.collections))
                        ForEach(node.children) { child in
                            row(.collection(child.id), in: library, plan: plan, among: [], depth: 1)
                                .disabled(plan.layout.isHidden(.collections) || plan.layout.isHidden(.collection(node.id)))
                        }
                    }
                } header: {
                    Text("Collections")
                } footer: {
                    Text("Anything other items are filed under is a collection.")
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
        case .collections: String(localized: "Collections")
        case .types: String(localized: "Types")
        case .folders: String(localized: "Folders")
        case .files: library.name(of: .files)
        case .type(let id): Self.typeNode(id, in: plan.types)?.label ?? id
        case .collection(let id): library.item(id)?.title ?? ""
        }
    }

    private func symbol(_ place: SidebarPlace, plan: SidebarPlan) -> String {
        switch place {
        case .inbox: "tray"
        case .recents: "clock"
        case .all: "note.text"
        case .favorites: "star"
        case .collections: "square.stack"
        case .types: "square.grid.2x2"
        case .folders: "folder"
        case .files: "doc"
        case .type(let id): Self.typeNode(id, in: plan.types)?.symbol ?? TypeSymbol.fallback
        case .collection(let id): Self.collectionNode(id, in: plan.collections)?.symbol ?? "square.stack"
        }
    }

    private static func typeNode(_ id: String, in nodes: [TypeNode]) -> TypeNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = typeNode(id, in: node.children) { return found }
        }
        return nil
    }

    private static func collectionNode(_ id: ItemID, in nodes: [CollectionNode]) -> CollectionNode? {
        nodes.lazy.compactMap { $0.id == id ? $0 : $0.children.first { $0.id == id } }.first
    }
}
