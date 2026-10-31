import MarfaIcons
import SwiftUI

struct SidebarTypePicker: View {
    @CurrentLibrary private var library
    @Environment(Libraries.self) private var libraries
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Show Types").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(SidebarPlan(library, layout: libraries.sidebarLayout).types) { node in
                        TypeToggleRow(node: node)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 360)
            HStack {
                Button("Show All") { libraries.updateSidebarLayout { $0.showAllTypes() } }
                    .disabled(!libraries.sidebarLayout.hidesTypes)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

/// A type's switch and, indented under it, its subtypes'. A hidden type dims the switches below it.
private struct TypeToggleRow: View {
    @Environment(Libraries.self) private var libraries
    let node: TypeNode
    var parentHidden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding {
                !libraries.sidebarLayout.isHidden(.type(node.id))
            } set: { shown in
                libraries.updateSidebarLayout { $0.setHidden(.type(node.id), !shown) }
            }) {
                Label { Text(node.label) } icon: { TypeIcon(name: node.icon) }
            }
            .toggleStyle(.checkbox)
            .disabled(parentHidden)
            ForEach(node.children) { child in
                TypeToggleRow(node: child, parentHidden: parentHidden || libraries.sidebarLayout.isHidden(.type(node.id)))
                    .padding(.leading, 16)
            }
        }
    }
}
