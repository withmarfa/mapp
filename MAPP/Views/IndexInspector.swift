import SwiftUI

/// The right sidebar of an index page: the chosen container, with no buttons. It shows what the container holds
/// (its latest items and the types in it), then the facts of the container. With nothing chosen it is empty, so the
/// page beside it already says that nothing is.
struct IndexInspector: View {
    @CurrentLibrary private var library
    let choice: IndexChoice
    /// Every row of the page, so a container left out by the tab or the search stays shown until it goes.
    let rows: [IndexRow]
    let open: (IndexRow) -> Void

    var body: some View {
        if let row = choice.row(in: rows) {
            IndexInspectorContent(row: row, library: library, open: open)
                .id(row.id)
        } else {
            Color.clear
        }
    }
}

private struct IndexInspectorContent: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    let row: IndexRow
    let library: any ItemLibrary
    let open: (IndexRow) -> Void

    private static let latestShown = 4

    private var items: [Item] { library.items(in: row.place) }

    var body: some View {
        let latest = IndexRows.newest(items, limit: Self.latestShown)
        ScrollView {
            VStack(alignment: .leading, spacing: InspectorMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.title).font(.title3.weight(.semibold)).lineLimit(3)
                    Text(subtitle).foregroundStyle(.secondary)
                }
                .padding(.horizontal, InspectorMetrics.headingInset)
                IndexInspectorSection(title: row.sourceCode == nil ? "Items" : "Latest", count: row.count, placeholder: latest.isEmpty ? "No Items" : nil) {
                    ForEach(latest) { item in
                        HStack {
                            Text(verbatim: item.displayTitle).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(item.modified, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if row.count > latest.count {
                        Button("Show All \(row.count)") { open(row) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                if !row.breakdown.isEmpty {
                    IndexInspectorSection(title: row.sourceCode == nil ? "Kinds" : "Writes") {
                        ForEach(row.breakdown) { share in
                            HStack(spacing: 6) {
                                TypeGlyph(id: share.icon)
                                    .foregroundStyle(TypeTone(icon: share.icon).color(for: scheme))
                                    .accessibilityHidden(true)
                                Text(verbatim: share.label).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(share.count, format: .number).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                IndexInspectorSection(title: "Details") { details }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("IndexInspector")
    }

    private var subtitle: String {
        let count = String(localized: "\(row.count) items")
        return (row.sourceCode == nil ? String(localized: "Collection") : String(localized: "Source")) + ", " + count
    }

    @ViewBuilder
    private var details: some View {
        if let code = row.sourceCode {
            detail("Kind", SourceCode.isApp(code) ? String(localized: "App") : String(localized: "Key"))
            detail("Code", code)
        } else if case .collection(let id) = row.place, let collection = library.item(id) {
            detail("Created", DateDisplay.text(of: collection.created, hasTime: false, place: .value, format: dateFormat))
            detail("Updated", DateDisplay.text(of: collection.modified, hasTime: false, place: .value, format: dateFormat))
            if !row.sourceName.isEmpty { detail("Source", row.sourceName) }
        }
    }

    private func detail(_ name: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(verbatim: value).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// A heading above a box whose rows are the content, as the item's right sidebar draws its sections, folding on a click.
private struct IndexInspectorSection<Content: View>: View {
    let title: LocalizedStringKey
    var count: Int?
    var placeholder: LocalizedStringKey?
    @ViewBuilder let content: Content
    @State private var isOpen = true

    var body: some View {
        InspectorSection(
            title: title, count: count, isOpen: $isOpen, identifier: "IndexInspectorSection", placeholder: placeholder,
            add: { _ in EmptyView() }
        ) { content }
    }
}
