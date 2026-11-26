import Foundation

/// Which items a layout drawn a page at a time draws (`Browser.listDrawn`): the first `head` items, and a page around the
/// chosen item where it stands far past them, so a link to an item near the end of a long list draws a page, not
/// everything up to it. Positions count the items in the layout's order, from its first.
nonisolated struct ListDrawn: Equatable, Sendable {
    /// The items drawn from the first.
    private(set) var head = Browser.listPage
    /// The items drawn around the chosen one, always after `head` with items between.
    private(set) var around: Range<Int>?

    private static var page: Int { Browser.listPage }

    /// The runs of items drawn of a layout of `count` items, in order.
    func runs(of count: Int) -> [Range<Int>] {
        var runs = [0..<min(head, count)]
        if let around, around.lowerBound < count { runs.append(around.lowerBound..<min(around.upperBound, count)) }
        return runs
    }

    /// Draws a page more after the run `run`, whose end came into view. Past the first run, the page around the chosen item
    /// grows toward it too, so whichever way the person scrolls to the gap between them, the items next to it are drawn.
    mutating func drawMore(after run: Int) {
        if run == 0 {
            head += Self.page
            if let around { self.around = max(head, around.lowerBound - Self.page)..<around.upperBound }
        } else if let around {
            self.around = around.lowerBound..<around.upperBound + Self.page
        }
        join()
    }

    /// Draws the item at `position`: the next page of a run where it stands just past one, as the arrow keys reach it, else
    /// a page around it in place of the last.
    mutating func show(_ position: Int) {
        if position < head || around?.contains(position) == true { return }
        if position < head + Self.page {
            head = (position / Self.page + 1) * Self.page
        } else if let around, position >= around.upperBound, position < around.upperBound + Self.page {
            self.around = around.lowerBound..<position + 1 + Self.page / 2
        } else if let around, position < around.lowerBound, position >= around.lowerBound - Self.page {
            self.around = max(head, position - Self.page / 2)..<around.upperBound
        } else {
            let lower = max(head, position - Self.page / 2)
            around = lower..<lower + Self.page
        }
        join()
    }

    /// Makes the two runs one where they meet.
    private mutating func join() {
        guard let around, around.lowerBound <= head else { return }
        head = max(head, around.upperBound)
        self.around = nil
    }

    /// The part of a section a layout draws: the items at `items` of section `section`, in the run `run`, and whether the
    /// run ends there with items after it, where the layout puts what draws the next page (`drawMore(after:)`).
    struct Part: Equatable, Sendable {
        let section: Int
        let items: Range<Int>
        let run: Int
        let endsRun: Bool
        /// Whether it is the first part drawn of its section, which then shows the section's heading.
        let startsSection: Bool
    }

    /// The parts drawn of sections holding `counts` items each. A section with no items to draw is drawn where a run reaches
    /// it, by its heading alone. In a grid of `columns`, a run that starts inside a section starts at the beginning of a
    /// row, so each card stands in the column a whole draw puts it in.
    func parts(of counts: [Int], columns: Int = 1) -> [Part] {
        let total = counts.reduce(0, +)
        let runs = runs(of: total)
        var parts: [Part] = []
        var start = 0
        for (section, count) in counts.enumerated() {
            defer { start += count }
            if count == 0 {
                if let run = runs.firstIndex(where: { $0.contains(start) || ($0.upperBound == total && start == total) }) {
                    parts.append(Part(section: section, items: 0..<0, run: run, endsRun: false, startsSection: true))
                }
                continue
            }
            var drawnTo = start
            for (index, run) in runs.enumerated() {
                let upper = min(run.upperBound, start + count)
                var lower = max(run.lowerBound, start)
                guard lower < upper else { continue }
                lower = max(drawnTo, start + (lower - start) / max(columns, 1) * max(columns, 1))
                parts.append(Part(
                    section: section, items: (lower - start)..<(upper - start), run: index,
                    endsRun: upper == run.upperBound && upper < total, startsSection: drawnTo == start))
                drawnTo = upper
            }
        }
        return parts
    }
}
