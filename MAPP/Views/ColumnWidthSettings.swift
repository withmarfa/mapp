import SwiftUI

/// A column whose default width the person sets in Settings. The split view only takes an ideal width per column, so
/// the app keeps these three values itself and hands each to its column as the ideal for a new window.
enum ColumnWidth: String, CaseIterable, Identifiable {
    case sidebar, list, settings

    var id: Self { self }

    /// The key the width is stored under in the app's defaults.
    var key: String { "interfaceDefaultWidth.\(rawValue)" }

    var defaultWidth: CGFloat {
        switch self {
        case .sidebar: 230
        case .list: 350
        case .settings: 290
        }
    }

    /// The narrowest and widest the column can be, which are the limits the column is given.
    var range: ClosedRange<CGFloat> {
        switch self {
        case .sidebar: 200...340
        case .list: 280...480
        case .settings: 200...340
        }
    }

    /// A stored value as the column's ideal width: the built-in default when nothing usable is stored, and the nearest
    /// width the column allows when the value lies outside its limits.
    func resolved(_ stored: Double?) -> CGFloat {
        guard let stored, stored.isFinite else { return defaultWidth }
        return min(range.upperBound, max(range.lowerBound, CGFloat(stored)))
    }

    func stored(in defaults: UserDefaults = .standard) -> CGFloat {
        resolved(defaults.object(forKey: key) as? Double)
    }
}

/// Settings for the width a column starts at in a new window. A width dragged in a window is that window's own and
/// never changes these.
struct ColumnWidthOptions: View {
    private var registry = ColumnWidthRegistry.shared

    var body: some View {
        ForEach(ColumnWidth.allCases) { ColumnWidthRow(column: $0) }
        HStack {
            Button("Reset Widths") {
                for column in ColumnWidth.allCases { UserDefaults.standard.removeObject(forKey: column.key) }
            }
            .accessibilityIdentifier("ColumnWidthsReset")
            Button("Use Current Widths") {
                guard let front = registry.front else { return }
                for column in ColumnWidth.allCases {
                    UserDefaults.standard.set(Double(column.resolved(Double(front.width(of: column)))), forKey: column.key)
                }
            }
            .disabled(registry.front == nil)
            .help(registry.front == nil ? "Open a window to use its column widths." : "Make the widths set in this window the defaults for new windows.")
            .accessibilityIdentifier("ColumnWidthsUseCurrent")
        }
    }
}

private struct ColumnWidthRow: View {
    let column: ColumnWidth
    @AppStorage private var stored: Double

    init(column: ColumnWidth) {
        self.column = column
        _stored = AppStorage(wrappedValue: Double(column.defaultWidth), column.key)
    }

    private var width: Binding<Double> {
        Binding { Double(column.resolved(stored)) } set: { stored = Double(column.resolved($0)) }
    }

    private var title: LocalizedStringKey {
        switch column {
        case .sidebar: "Sidebar"
        case .list: "List"
        case .settings: "Settings"
        }
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text("\(Int(width.wrappedValue)) pt").monospacedDigit().foregroundStyle(.secondary)
                Stepper(title, value: width, in: Double(column.range.lowerBound)...Double(column.range.upperBound), step: 10)
                    .labelsHidden()
            }
        }
        .accessibilityIdentifier("ColumnWidth-\(column.rawValue)")
    }
}

/// The widths a person has set in one main window by dragging a divider. Each column starts at the width set in
/// Settings. The split view takes a column's ideal width only when it is built, and lays out at other widths while it
/// settles and whenever the window changes shape, so only a drag counts: a width read from the layout would be copied
/// back as the ideal and the column would open at whatever width the layout last squeezed it to.
@MainActor
final class ColumnWidthTracker {
    private var widths: [ColumnWidth: CGFloat]

    init(defaults: UserDefaults = .standard) {
        widths = Dictionary(uniqueKeysWithValues: ColumnWidth.allCases.map { ($0, $0.stored(in: defaults)) })
    }

    func width(of column: ColumnWidth) -> CGFloat { widths[column] ?? column.defaultWidth }

    /// Keeps a width the person dragged a column to; a width outside the column's limits is not one they can have set.
    func record(_ width: CGFloat, for column: ColumnWidth) {
        guard width.isFinite, column.range.contains(width) else { return }
        widths[column] = width
    }

    /// The width of each column from the right edges of a split view's items, first to last. A sidebar that floats over
    /// the content starts at the left edge like the content does, so a column runs from the previous item's right edge.
    static func columnWidths(rightEdges: [CGFloat]) -> [CGFloat] {
        rightEdges.enumerated().map { index, edge in
            max(0, edge - (index == 0 ? 0 : max(0, rightEdges[index - 1])))
        }
    }
}

/// The tracker of the main window in front, which Settings reads for Use Current Widths. It holds the tracker weakly,
/// so a closed window leaves it empty.
@MainActor @Observable
final class ColumnWidthRegistry {
    static let shared = ColumnWidthRegistry()
    weak var front: ColumnWidthTracker?

    /// Makes this window's tracker the front one; a window that stops being in front gives it up only if it still holds it.
    func windowBecame(active: Bool, tracker: ColumnWidthTracker) {
        if active { front = tracker } else if front === tracker { front = nil }
    }
}
