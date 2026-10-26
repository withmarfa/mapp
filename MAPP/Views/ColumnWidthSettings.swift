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
        case .list: 340
        case .settings: 260
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
    var body: some View {
        ForEach(ColumnWidth.allCases) { ColumnWidthRow(column: $0) }
        Button("Reset Widths") {
            for column in ColumnWidth.allCases { UserDefaults.standard.removeObject(forKey: column.key) }
        }
        .accessibilityIdentifier("ColumnWidthsReset")
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
