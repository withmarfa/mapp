import SwiftUI

/// The list of Marfa's types, for the window's list column: item types as a tree by parent, then edge types.
/// Searching shows the tree open throughout and flat, since a match under a closed parent would be out of sight.
struct TypesListView: View {
    @Bindable var browser: TypesBrowser

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: Binding { browser.selection } set: { browser.select($0) }) {
                let rows = browser.itemRows
                if !rows.isEmpty {
                    Section("Item types") {
                        if browser.isSearching {
                            ForEach(rows) { node in
                                TypeRow(node: node)
                                    .padding(.leading, CGFloat(node.depth) * 16)
                            }
                        } else {
                            ForEach(browser.itemTree) { node in
                                TypeBranch(node: node, browser: browser)
                            }
                        }
                    }
                }
                let edges = browser.edgeTypes
                if !edges.isEmpty {
                    Section("Edge types") {
                        ForEach(edges, id: \.selection) { edge in
                            EdgeTypeRow(edge: edge)
                        }
                    }
                }
            }
            .listStyle(.inset)
            // The rows a choice opens are not laid out until the change has been drawn.
            .onChange(of: browser.selection) { _, selection in
                guard let selection else { return }
                Task { proxy.scrollTo(selection) }
            }
        }
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

/// A type and, in a group the browser holds open or shut, the types below it.
private struct TypeBranch: View {
    let node: TypeNode
    let browser: TypesBrowser

    var body: some View {
        if let children = node.children {
            DisclosureGroup(
                isExpanded: Binding { browser.isExpanded(node.type.id) } set: { browser.setExpanded(node.type.id, $0) }
            ) {
                ForEach(children) { child in
                    TypeBranch(node: child, browser: browser)
                }
            } label: {
                TypeRow(node: node)
            }
            .tag(node.id)
        } else {
            TypeRow(node: node)
                .tag(node.id)
        }
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
        .accessibilityHint(node.matchesSearch ? "" : String(localized: "Shown because a type below it matches the search."))
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
