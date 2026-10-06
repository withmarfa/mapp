import SwiftUI

/// The list of Marfa's types, for the window's list column: item types as a tree by parent, then edge types.
/// Searching opens the tree throughout, since a match under a closed parent would be out of sight.
struct TypesListView: View {
    @Bindable var browser: TypesBrowser

    var body: some View {
        List(selection: Binding { browser.selection } set: { browser.select($0) }) {
            let rows = browser.itemRows
            if !rows.isEmpty {
                Section("Item Types") {
                    if browser.isSearching {
                        ForEach(rows) { node in
                            TypeRow(node: node)
                                .padding(.leading, CGFloat(node.depth) * 16)
                        }
                    } else {
                        OutlineGroup(browser.itemTree, children: \.children) { node in
                            TypeRow(node: node)
                        }
                    }
                }
            }
            let edges = browser.edgeTypes
            if !edges.isEmpty {
                Section("Edge Types") {
                    ForEach(edges, id: \.selection) { edge in
                        EdgeTypeRow(edge: edge)
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if !browser.hasResults {
                if browser.isSearching {
                    ContentUnavailableView.search(text: browser.searchText)
                } else {
                    ContentUnavailableView(
                        "No Types", systemImage: "square.stack.3d.up",
                        description: Text("This library has no types to show."))
                }
            }
        }
        .accessibilityIdentifier("MarfaTypesList")
    }
}

private struct TypeRow: View {
    let node: TypeNode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(node.type.label)
                Text(node.type.id.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            // A type shown only for the matches below it reads as context.
            .opacity(node.matchesSearch ? 1 : 0.6)
            Spacer(minLength: 0)
            if node.subtypeCount > 0 {
                Text("^[\(node.subtypeCount) subtype](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("MarfaTypeRow.\(node.type.id.rawValue)")
    }
}

private struct EdgeTypeRow: View {
    let edge: EdgeTypeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(edge.label)
            Text(edge.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("MarfaTypeRow.\(edge.id)")
    }
}
