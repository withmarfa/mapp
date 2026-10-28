import AppKit
import SwiftUI
import Testing
@testable import MAPP

/// The toolbar sizes an item from what it reports. These pin that the title reports the width its own text needs,
/// whatever width the toolbar happens to offer while it places the item.
struct ScrolledItemTitleTests {
    /// The width a hosting view settles on for a view that is offered `width` (nothing, when it is `nil`).
    private func width(of title: String, offered width: CGFloat?) -> CGFloat {
        let title = ScrolledItemTitle(title: title)
        guard let width else { return NSHostingView(rootView: title).fittingSize.width }
        return NSHostingView(rootView: OfferedWidth(width: width) { title }).fittingSize.width
    }

    @Test func aTitleReportsItsOwnWidthWhateverIsOffered() {
        let title = "146a Folder watch redraw"
        let own = width(of: title, offered: nil)
        #expect(own > 100 && own < ScrolledItemTitle.widest)
        for offered in [CGFloat(0), 20, 60, 500, 5_000] {
            #expect(width(of: title, offered: offered) == own, "offered \(offered)")
        }
    }

    @Test func aShortTitleIsNeverStretchedOrCut() {
        #expect(width(of: "14", offered: 20) == width(of: "14", offered: 500))
        #expect(width(of: "14", offered: 20) < 40)
    }

    @Test func aLongTitleStopsAtTheWidest() {
        let title = String(repeating: "A very long title ", count: 20)
        for offered in [CGFloat(20), 500, 5_000] {
            #expect(width(of: title, offered: offered) == ScrolledItemTitle.widest)
        }
    }

    @Test func theToolbarSettingsAreResetWithTheOtherInterfaceSettings() {
        #expect(InterfaceKey.all.contains(InterfaceKey.showsScrolledTitle))
        #expect(InterfaceKey.all.contains(InterfaceKey.showsPageToolbarBackground))
    }
}

/// Offers its content one width, as a toolbar does while it places an item.
private struct OfferedWidth<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View { Offer(width: width) { content() } }

    private struct Offer: Layout {
        let width: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: width, height: nil))
        }
    }
}
