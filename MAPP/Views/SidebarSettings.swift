import SwiftUI

/// The Sidebar pane of Settings: every place the open library's sidebar can show, each with a checkbox to show or
/// hide it, in the order the sidebar uses. Dragging a row moves it within its group. The choices belong to the
/// library that is open, so each library keeps its own sidebar.
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
        List {
            Section {
                ForEach(plan.top, id: \.key) { place in
                    row(place, title: title(place, in: library), in: plan)
                }
                .onMove { source, destination in
                    libraries.updateSidebarLayout { $0.move(plan.top, fromOffsets: source, toOffset: destination) }
                }
            } header: {
                Text("Places")
            }
            Section {
                row(.favorites, title: title(.favorites, in: library), in: plan)
            } footer: {
                Text("Favorites lists the items you’ve marked as favorites.")
            }
            Section {
                ForEach(plan.library, id: \.key) { place in
                    row(place, title: title(place, in: library), in: plan)
                }
                .onMove { source, destination in
                    libraries.updateSidebarLayout { $0.move(plan.library, fromOffsets: source, toOffset: destination) }
                }
            } header: {
                Text("Library")
            }
            if !plan.types.isEmpty {
                Section {
                    ForEach(plan.types) { type in
                        row(.type(type.id), title: type.label, in: plan)
                            .disabled(plan.layout.isHidden(.types))
                    }
                    .onMove { source, destination in
                        libraries.updateSidebarLayout {
                            $0.move(plan.types, by: { SidebarPlace.type($0.id).key }, fromOffsets: source, toOffset: destination)
                        }
                    }
                } header: {
                    Text("Types")
                } footer: {
                    Text("A type appears when the library has an item of that type. Drag to reorder.")
                }
            }
        }
        .listStyle(.inset)
        .accessibilityIdentifier("SidebarSettings")
    }

    private func row(_ place: SidebarPlace, title: String, in plan: SidebarPlan) -> some View {
        Toggle(isOn: Binding {
            plan.isShown(place)
        } set: { isShown in
            libraries.updateSidebarLayout { $0.setHidden(place, !isShown) }
        }) {
            Text(title).interfaceFont(.body)
        }
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("SidebarSetting-\(place.key)")
    }

    private func title(_ place: SidebarPlace, in library: any ItemLibrary) -> String {
        switch place {
        case .inbox: library.name(of: .inbox)
        case .all: library.name(of: .allNotes)
        case .favorites: library.name(of: .favorites)
        case .projects: library.name(of: .itemType(TypeID.project.rawValue))
        case .types: String(localized: "Types")
        case .folders: String(localized: "Folders")
        case .files: library.name(of: .files)
        case .recentlyDeleted: library.name(of: .recentlyDeleted)
        case .type(let id): library.name(of: .itemType(id.rawValue))
        }
    }
}
