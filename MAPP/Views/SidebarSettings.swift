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
        let folderRows = plan.library.filter { $0 == .folders || $0 == .files }
        let typeRows = plan.types.map { SidebarPlace.type($0.id) }
        return Form {
            Section("Places") {
                group(plan.top, in: library, plan: plan)
                row(.favorites, in: library, plan: plan, among: [])
            }
            if plan.library.contains(.projects) {
                Section("Projects") {
                    row(.projects, title: String(localized: "Show Projects"), in: library, plan: plan, among: [])
                }
            }
            if plan.library.contains(.types) {
                Section {
                    row(.types, title: String(localized: "Show Types"), in: library, plan: plan, among: [])
                    group(typeRows, in: library, plan: plan, disabled: plan.layout.isHidden(.types))
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
        }
        .settingsForm()
        .accessibilityIdentifier("SidebarSettings")
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
        _ place: SidebarPlace, title: String? = nil, in library: any ItemLibrary, plan: SidebarPlan, among places: [SidebarPlace]
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
                Image(systemName: symbol(place)).interfaceFont(.body)
            }
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
        case .all: library.name(of: .allNotes)
        case .favorites: library.name(of: .favorites)
        case .projects: library.name(of: .itemType(TypeID.project.rawValue))
        case .types: String(localized: "Types")
        case .folders: String(localized: "Folders")
        case .files: library.name(of: .files)
        case .type(let id): plan.types.first { $0.id == id }?.label ?? library.name(of: .itemType(id.rawValue))
        }
    }

    private func symbol(_ place: SidebarPlace) -> String {
        switch place {
        case .inbox: "tray"
        case .all: "note.text"
        case .favorites: "star"
        case .projects: "square.stack"
        case .types: "square.grid.2x2"
        case .folders: "folder"
        case .files: "doc"
        case .type(let id): TypeSymbol.name(for: id)
        }
    }
}
