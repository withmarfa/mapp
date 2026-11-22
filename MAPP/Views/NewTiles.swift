import SwiftUI

/// The New row of the Items page: a tile for each type the person keeps there, tinted with the type's color, which opens
/// quick add in that type. The types and their order are a MAPP setting (`NewRowTypes`), synced with the rest. While Edit's popover is out
/// each tile carries a minus badge that takes its type out of the row.
struct NewTiles: View {
    @CurrentLibrary private var library
    @AppStorage(NewRowTypes.key) private var kept: String?
    @Environment(\.colorScheme) private var scheme
    let browser: Browser

    /// The measures of a tile.
    private static let width: CGFloat = 132
    private static let height: CGFloat = 78
    private static let radius: CGFloat = 12

    var body: some View {
        let types = NewRowTypes.shown(QuickAdd.types(in: library), kept: kept)
        VStack(alignment: .leading, spacing: 8) {
            Text("New")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, IndexMetrics.side)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(types) { type in
                        tile(type, row: types)
                    }
                }
                // Room for the minus badges, which sit past the tiles' corners.
                .padding(.horizontal, IndexMetrics.side)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            .scrollClipDisabled()
            .padding(.vertical, -6)
        }
        .padding(.top, NewRowMetrics.gapAboveLabel)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("NewTiles")
    }

    private func tile(_ type: ItemTypeOption, row: [ItemTypeOption]) -> some View {
        let tone = TypeTone(icon: type.icon)
        let looks = ChipLooks.current
        return Button {
            browser.openQuickAdd(typeID: type.id.rawValue, in: library)
        } label: {
            VStack(spacing: 6) {
                Image(typeGlyph: type.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(tone.ink(looks, for: scheme))
                Text(verbatim: type.label)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(tone.ink(looks, for: scheme))
            }
            .padding(.horizontal, 8)
            .frame(width: Self.width, height: Self.height)
            .background(tone.fill(looks.markOpacity, for: scheme), in: .rect(cornerRadius: Self.radius, style: .continuous))
            .contentShape(.rect(cornerRadius: Self.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!QuickAdd.isAvailable(in: library))
        .overlay(alignment: .topLeading) {
            if browser.isEditingNewRow {
                Button {
                    kept = NewRowTypes.toggled(type.id.rawValue, row: row)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray)
                        .font(.system(size: 18))
                        .background(Circle().fill(.background).padding(2))
                }
                .buttonStyle(.plain)
                .offset(x: -6, y: -6)
                .help("Remove \(type.label) From New")
                .accessibilityLabel("Remove \(type.label) From New")
            }
        }
        .accessibilityIdentifier("NewTile.\(type.id.rawValue)")
    }
}

private enum NewRowMetrics {
    /// The space between the tabs and the row's label.
    static let gapAboveLabel: CGFloat = 12
}

/// What Edit opens: the types a new item can be, those in the New row first, ticked, in the row's order and draggable
/// to change it, then the others, unticked. A click on a type's line adds it to the row or takes it out.
struct NewRowEditor: View {
    @CurrentLibrary private var library
    @AppStorage(NewRowTypes.key) private var kept: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let listed = NewRowTypes.listed(QuickAdd.types(in: library), kept: kept)
        List {
            Section {
                ForEach(listed.inRow) { line($0, isIn: true, row: listed.inRow) }
                    .onMove { kept = NewRowTypes.moved(listed.inRow, from: $0, to: $1) }
            }
            if !listed.others.isEmpty {
                Section {
                    ForEach(listed.others) { line($0, isIn: false, row: listed.inRow) }
                }
            }
        }
        .listStyle(.plain)
        .frame(width: 260, height: min(CGFloat(listed.inRow.count + listed.others.count) * 28 + 24, 360))
        .accessibilityIdentifier("NewRowEditor")
    }

    private func line(_ type: ItemTypeOption, isIn: Bool, row: [ItemTypeOption]) -> some View {
        Button {
            kept = NewRowTypes.toggled(type.id.rawValue, row: row)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(isIn ? 1 : 0)
                    .frame(width: 14)
                    .accessibilityHidden(true)
                Image(typeGlyph: type.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(TypeTone(icon: type.icon).color(for: scheme))
                    .accessibilityHidden(true)
                Text(verbatim: type.label)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isIn ? .isSelected : [])
    }
}
