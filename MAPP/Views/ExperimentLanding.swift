#if DEBUG
import MarfaIcons
import SwiftUI

/// The sidebar experiment's landing page for Items, in the manner of the Claude app's Artifacts page: a title, a row of
/// chips to make something new, then cards for what changed lately. A card opens its item as the list does. Its text
/// is not localized.
struct ExperimentLanding: View {
    @CurrentLibrary private var library
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    let browser: Browser
    let order: NoteOrder
    let showsCreation: Bool

    /// The corner of the page's chips and cards; continuous, between square and round.
    fileprivate static let corner: CGFloat = 14

    var body: some View {
        let recent = Array(library.items(in: .recents).prefix(12))
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "Items")
                        .interfaceFont(.largeTitle.weight(.medium))
                        .fontDesign(.serif)
                    Text(verbatim: summary)
                        .interfaceFont(.body)
                        .foregroundStyle(.secondary)
                }
                makeSomethingNew
                recentItems(recent)
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
        .navigationTitle(Text(verbatim: "Items"))
        .toolbar {
            if showsCreation {
                ToolbarItem(id: "landingNewItem") { NewItemButton(browser: browser) }
            }
        }
        .accessibilityIdentifier("ExperimentLanding")
    }

    private var summary: String {
        let count = library.count(in: .allNotes)
        return count == 1 ? "1 item in this library" : "\(count) items in this library"
    }

    // MARK: Make something new

    private var makeSomethingNew: some View {
        let split = ExperimentChips.split(QuickAdd.types(in: library), usedMost: library.itemTypeCounts.map(\.id))
        return VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Make something new")
                .interfaceFont(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(split.shown) { option in
                        Button { browser.openQuickAdd(typeID: option.id.rawValue, in: library) } label: {
                            ChipLabel(title: option.label, icon: .type(option.icon))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ExperimentMake-\(option.id.rawValue)")
                    }
                    if !split.more.isEmpty {
                        Menu {
                            ForEach(split.more) { option in
                                Button { browser.openQuickAdd(typeID: option.id.rawValue, in: library) } label: {
                                    Label(option.label, typeIcon: option.icon)
                                }
                            }
                        } label: {
                            ChipLabel(title: "More", icon: .symbol("plus"))
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityIdentifier("ExperimentMakeMore")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Recent

    @ViewBuilder private func recentItems(_ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verbatim: "Recent")
                    .interfaceFont(.headline)
                Spacer()
                Button { browser.landing = false } label: {
                    Text(verbatim: "See all items")
                }
                .buttonStyle(.link)
                .interfaceFont(.subheadline)
                .accessibilityIdentifier("ExperimentSeeAll")
            }
            if items.isEmpty {
                Text(verbatim: "Nothing here yet. Make something new above.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 16)], spacing: 16) {
                    ForEach(items) { item in
                        Button { browser.reveal(item, in: library, order: order) } label: {
                            LandingCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ExperimentCard-\(item.id.rawValue)")
                    }
                }
            }
        }
    }
}

/// A chip: a mark and a name in a soft rounded shape with a hairline edge.
private struct ChipLabel: View {
    let title: String
    let icon: RowIcon
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            RowIconImage(icon: icon).foregroundStyle(.secondary)
            Text(verbatim: title)
        }
        .interfaceFont(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary), in: shape)
        .overlay(shape.strokeBorder(.quaternary, lineWidth: 1))
        .contentShape(shape)
        .onHover { isHovering = $0 }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: ExperimentLanding.corner, style: .continuous) }
}

/// A card for one item: its title, a few lines of its text, its type and when it changed.
private struct LandingCard: View {
    @CurrentLibrary private var library
    let item: Item
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title.isEmpty ? String(localized: "Untitled") : item.title)
                .interfaceFont(.headline)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(verbatim: item.preview)
                .interfaceFont(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            HStack {
                HStack(spacing: 5) {
                    TypeIcon(name: library.catalogue.icon(for: item.type))
                    Text(verbatim: library.catalogue.label(for: item.type)).lineLimit(1)
                }
                .interfaceFont(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer(minLength: 8)
                Text(item.modified, format: .relative(presentation: .named))
                    .interfaceFont(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary), in: shape)
        .overlay(shape.strokeBorder(.quaternary, lineWidth: 1))
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .foregroundStyle(.primary)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: ExperimentLanding.corner, style: .continuous) }
}
#endif
