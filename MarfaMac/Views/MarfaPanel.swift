import SwiftUI

/// What the Marfa's panel says, worked out once when it opens: the Marfa's name and size, its sources by their newest
/// item, and where it is. The app holds one Marfa at a time, so that is the only one listed.
struct MarfaPanelContent {
    struct Update: Identifiable, Hashable {
        let code: String
        let name: String
        let icon: RowIcon
        let latest: Date

        var id: String { code }
    }

    /// How many sources the panel shows before Show More.
    static let shownUpdates = 3

    let name: String
    let address: String
    let count: Int
    /// Newest first.
    let updates: [Update]

    init(library: any ItemLibrary, name: String, address: String) {
        self.name = name
        self.address = address
        count = library.count(in: .library)
        updates = IndexRows.groupedBySource(library.activeItems)
            .compactMap { source in
                source.items.map(\.modified).max().map {
                    Update(
                        code: source.code, name: library.sourceName(source.code),
                        icon: SourceTile.icon(for: library.sources.info(source.code)), latest: $0)
                }
            }
            .sorted { $0.latest > $1.latest }
    }

    static func items(_ count: Int) -> String {
        count == 1 ? String(localized: "1 item") : String(localized: "\(count.formatted()) items")
    }

    /// "1,205 items. Updated 2 minutes ago.", or the size alone while no sync has finished or no server is asked.
    static func head(count: Int, lastSynced: Date?, now: Date) -> String {
        guard let lastSynced else { return items(count) + "." }
        return items(count) + ". " + SyncFootLine.updated(since: lastSynced, now: now) + "."
    }
}

/// The popover the sidebar's foot opens: the Marfa's name and size, its latest updates, and the Marfa the app is
/// connected to. A latest update opens its source's place.
struct MarfaPanel: View {
    @State private var showsAll = false
    let content: MarfaPanelContent
    /// Nil where no server is asked, so no sync is told.
    let lastSynced: Date?
    let open: (Place) -> Void
    let addMarfa: () -> Void

    static let width: CGFloat = 300
    private static let rowHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            if !content.updates.isEmpty {
                Divider()
                updates
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            Divider()
            marfas
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(width: Self.width)
        .accessibilityIdentifier("MarfaPanel")
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: content.name)
                .interfaceFont(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            TimelineView(.periodic(from: lastSynced ?? .now, by: 60)) { context in
                Text(verbatim: MarfaPanelContent.head(count: content.count, lastSynced: lastSynced, now: context.date))
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Latest updates

    private var updates: some View {
        let shown = showsAll ? content.updates : Array(content.updates.prefix(MarfaPanelContent.shownUpdates))
        let hidden = content.updates.count - shown.count
        return VStack(alignment: .leading, spacing: 0) {
            heading(Text("Latest Updates"))
            // A Marfa with many sources scrolls inside the panel rather than grow past the window.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(shown) { update in
                        PanelRow(action: { open(.source(update.code)) }) {
                            Self.symbol(update.icon)
                            Text(verbatim: update.name).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(verbatim: DateDisplay.text(of: update.latest, place: .list, format: .stored()))
                                .interfaceFont(.callout)
                                .foregroundStyle(.tertiary)
                        }
                        .accessibilityIdentifier("MarfaPanelUpdate")
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: Self.rowHeight * CGFloat(min(shown.count, 8)))
            if hidden > 0 {
                PanelRow(action: { showsAll = true }) {
                    Color.clear.frame(width: 16, height: 1)
                    Text("Show \(hidden) More")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityIdentifier("MarfaPanelShowMore")
            }
        }
    }

    // MARK: Marfas

    private var marfas: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading(Text("Marfas")) {
                Button(action: addMarfa) {
                    Image(systemName: "plus")
                        .interfaceFont(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Use Another Marfa")
                .accessibilityLabel(Text("Use Another Marfa"))
                .accessibilityIdentifier("MarfaPanelAdd")
            }
            PanelRow(action: nil) {
                Image(systemName: "checkmark")
                    .interfaceFont(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(verbatim: content.name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Text(verbatim: content.address)
                    .interfaceFont(.callout)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isSelected)
        }
    }

    // MARK: Parts

    private func heading(_ title: Text) -> some View {
        heading(title) { EmptyView() }
    }

    private func heading<Trailing: View>(_ title: Text, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            title
                .interfaceFont(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    @ViewBuilder private static func symbol(_ icon: RowIcon) -> some View {
        Group {
            switch icon {
            case .symbol(let name): Image(systemName: name)
            case .type(let id): Image(typeGlyph: id)
            }
        }
        .interfaceFont(.callout)
        .foregroundStyle(.secondary)
        .frame(width: 16)
        .accessibilityHidden(true)
    }
}

/// One line of the panel, 28 points high with a soft fill under the pointer where it does something.
private struct PanelRow<Content: View>: View {
    @State private var isHovering = false
    /// Nil for a line that only says something.
    let action: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        if let action {
            Button(action: action) { line }
                .buttonStyle(.plain)
        } else {
            line
        }
    }

    private var line: some View {
        HStack(spacing: 9) { content }
            .interfaceFont(.body)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(isHovering && action != nil ? 0.06 : 0)))
            .contentShape(.rect)
            .onHover { isHovering = $0 }
    }
}
