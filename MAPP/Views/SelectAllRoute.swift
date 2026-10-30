import AppKit
import SwiftUI

extension View {
    /// Makes Select All on this list set its selection through `selectAll` rather than through the table behind it.
    /// Apply it to a `List` in a column of a `NavigationSplitView` that can hold many rows; see `SelectAllRoute`.
    func selectsAll(_ selectAll: @escaping () -> Void) -> some View {
        background(SelectAllRoute(selectAll: selectAll))
    }
}

/// SwiftUI treats the selection of a list in a split view's column as navigation. For every row the table adds to its
/// selection, SwiftUI makes that row's view, even far out of sight, to find out what selecting the row should do, and
/// AppKit then removes each view again at a cost that grows with how many there are. Select All on a list of about
/// ten thousand items held the window for over a minute. A selection set through the list's binding makes no row's
/// view, so `MAPPApplication` sends Select All for a list that has this route to the route instead of to its table.
struct SelectAllRoute: NSViewRepresentable {
    let selectAll: () -> Void

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) { probe.selectAll = selectAll }

    final class Probe: NSView {
        var selectAll: (() -> Void)?
        private weak var table: NSTableView?
        private static let inWindows = NSHashTable<Probe>.weakObjects()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            table = nil
            if window == nil { Self.inWindows.remove(self) } else { Self.inWindows.add(self) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// The route of the list whose table this is, if it has one.
        static func route(for table: NSTableView) -> (() -> Void)? {
            inWindows.allObjects.first { $0.window === table.window && $0.listTable() === table }?.selectAll
        }

        /// Looked for when Select All is sent, since SwiftUI may replace the table as the list changes.
        private func listTable() -> NSTableView? {
            if table == nil || table?.window !== window { table = nearestTable() }
            return table
        }
    }
}

/// The app's `NSApplication`, which sends Select All for a list with a `SelectAllRoute` to that route. The menu
/// item and its key equivalent both send their action through `sendAction(_:to:from:)`.
@objc(MAPPApplication)
final class MAPPApplication: NSApplication {
    override func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
        if action == #selector(NSResponder.selectAll(_:)),
           let table = (target ?? self.target(forAction: action, to: nil, from: sender)) as? NSTableView,
           let selectAll = SelectAllRoute.Probe.route(for: table) {
            selectAll()
            return true
        }
        return super.sendAction(action, to: target, from: sender)
    }
}
