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
            .help(registry.front == nil ? "Open a window to use its column widths." : "Make the widths this window shows the defaults for new windows.")
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

/// What one main window knows of its columns' widths. Each starts at the width set in Settings; a width measured
/// in the window replaces it. The split view lays out narrow for a moment whenever it is built, so a measurement is
/// kept only once the layout has settled; one taken earlier would be copied back as the column's ideal width and the
/// column would open at its minimum.
@MainActor
final class ColumnWidthTracker {
    private var widths: [ColumnWidth: CGFloat]
    private(set) var isSettling = true

    init(defaults: UserDefaults = .standard) {
        widths = Dictionary(uniqueKeysWithValues: ColumnWidth.allCases.map { ($0, $0.stored(in: defaults)) })
    }

    func width(of column: ColumnWidth) -> CGFloat { widths[column] ?? column.defaultWidth }

    func record(_ width: CGFloat, for column: ColumnWidth) {
        guard !isSettling, width.isFinite, width >= column.range.lowerBound else { return }
        widths[column] = width
    }

    /// Called as the split view is built again; measurements are ignored until `endSettling`.
    func beginSettling() { isSettling = true }
    func endSettling() { isSettling = false }
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
