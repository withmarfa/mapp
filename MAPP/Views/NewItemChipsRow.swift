import MarfaIcons
import SwiftUI

extension View {
    /// A row of chips to make something new, above a page the app already has. The page is the ordinary gallery,
    /// table, board, timeline or index, with its own toolbar, layout switcher and view options; the row shows only
    /// where `Browser.offersNewItemChips`. It is an inset and not a `safeAreaBar`, which draws a material of its own
    /// behind the row at the width of the scroll view, lighter than the window while the window is not in front;
    /// the page draws its band (`bandsToolbar`) once content is under the row.
    func newItemChips(_ browser: Browser) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if browser.offersNewItemChips {
                MakeSomethingNew(browser: browser)
            }
        }
    }
}

/// "Make something new": the four types with most items as chips, then a More menu with the rest. A chip opens quick
/// add on that type.
private struct MakeSomethingNew: View {
    @CurrentLibrary private var library
    let browser: Browser

    /// The corner of a chip; continuous, between square and round.
    fileprivate static let corner: CGFloat = 14

    var body: some View {
        let split = NewItemChips.split(QuickAdd.types(in: library), usedMost: library.itemTypeCounts.map(\.id))
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                Text("Make something new")
                    .interfaceFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
                ForEach(split.shown) { option in
                    Button { browser.openQuickAdd(typeID: option.id.rawValue, in: library) } label: {
                        ChipLabel(title: option.label, icon: .type(option.icon))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("MakeSomethingNew-\(option.id.rawValue)")
                }
                if !split.more.isEmpty {
                    Menu {
                        ForEach(split.more) { option in
                            Button { browser.openQuickAdd(typeID: option.id.rawValue, in: library) } label: {
                                Label(option.label, typeIcon: option.icon)
                            }
                        }
                    } label: {
                        ChipLabel(title: String(localized: "More"), icon: .symbol("plus"))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityIdentifier("MakeSomethingNewMore")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("MakeSomethingNew")
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
            Text(title)
        }
        .interfaceFont(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary), in: shape)
        .overlay(shape.strokeBorder(.quaternary, lineWidth: 1))
        .contentShape(shape)
        .onHover { isHovering = $0 }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: MakeSomethingNew.corner, style: .continuous) }
}
