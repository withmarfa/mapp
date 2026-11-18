import SwiftUI

extension View {
    /// Says the counts of an item are wanted while this view is on screen: they are asked for when it appears and let go
    /// when it disappears or is given another item, never while it draws (`ItemCounts.want`).
    func wantsCounts(of id: ItemID, _ queries: Set<CountQuery>, in counts: ItemCounts) -> some View {
        modifier(WantsCounts(counts: counts, wish: CountWish(id: id, queries: queries)))
    }
}

private struct CountWish: Hashable {
    let id: ItemID
    let queries: Set<CountQuery>
}

private struct WantsCounts: ViewModifier {
    let counts: ItemCounts
    let wish: CountWish
    /// What this view has asked to have counted, so the same is let go whatever the view's inputs have become.
    @State private var held: CountWish?

    func body(content: Content) -> some View {
        content
            .onAppear { move(to: wish) }
            .onDisappear { move(to: nil) }
            // A reused view, as a table's cell for another row, lets go of the old item and wants the new one.
            .onChange(of: wish) { _, new in if held != nil { move(to: new) } }
    }

    private func move(to next: CountWish?) {
        guard held != next else { return }
        if let held { for query in held.queries { counts.release([held.id], query) } }
        held = next
        if let next { for query in next.queries { counts.want([next.id], query) } }
    }
}
