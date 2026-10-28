#if DEBUG
import MarfaIcons
import SwiftUI

extension View {
    /// The experiment's landing: a row of chips to make something new, above a page the app already has. The page is
    /// the ordinary gallery, table, board, timeline or index, with its own toolbar, layout switcher and view options;
    /// the row shows only in the experiment style, and only where `Browser.offersExperimentLanding`.
    func experimentLanding(_ browser: Browser) -> some View {
        safeAreaBar(edge: .top, spacing: 0) {
            if SidebarStyle.selected == .experiment, browser.offersExperimentLanding {
                MakeSomethingNew(browser: browser)
            }
        }
    }
}

/// "Make something new": the four types with most items as chips, then a More menu with the rest. A chip opens quick
/// add on that type. Its text is not localized.
private struct MakeSomethingNew: View {
    @CurrentLibrary private var library
    let browser: Browser

    /// The corner of a chip; continuous, between square and round.
    fileprivate static let corner: CGFloat = 14

    var body: some View {
        let split = ExperimentChips.split(QuickAdd.types(in: library), usedMost: library.itemTypeCounts.map(\.id))
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                Text(verbatim: "Make something new")
                    .interfaceFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
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
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("ExperimentLanding")
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
        .padding(.vertical, 7)
        .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary), in: shape)
        .overlay(shape.strokeBorder(.quaternary, lineWidth: 1))
        .contentShape(shape)
        .onHover { isHovering = $0 }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: MakeSomethingNew.corner, style: .continuous) }
}
#endif
