import Charts
import SwiftUI

/// Counts by day with each series stacked in the order given.
struct SettingsUsageChart: View {
    struct Series {
        let name: String
        let tone: SettingsTokens.Tone
        /// One count per day, in the same order as the chart's days.
        let values: [Int]
    }

    let days: [Date]
    /// The instant the days were counted to, so the last day of that window reads Today.
    var now: Date = .now
    var calendar: Calendar = .current
    let series: [Series]
    @State private var plotWidth = SettingsTokens.Metric.column
    private typealias Metric = SettingsTokens.Metric.Usage

    private struct Segment {
        let day: Int
        let series: Series
        let start: Double
        let end: Double
    }

    private var segments: [Segment] {
        days.indices.flatMap { day in
            var start = 0.0
            return series.map { series in
                let count = series.values.indices.contains(day) ? max(0, series.values[day]) : 0
                let end = start + Double(count)
                defer { start = end }
                return Segment(day: day, series: series, start: start, end: end)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.chartGap) {
            chart
                .padding(.top, Metric.chartTop)
            UsageLegend(entries: series.map { series in
                let total = series.values.prefix(days.count).reduce(0.0) { $0 + Double(max(0, $1)) }
                return UsageLegend.Entry(name: series.name, value: total.formatted(.number.precision(.fractionLength(0))), tone: series.tone)
            })
            .padding(.top, Metric.legendTop)
        }
        .padding(.horizontal, SettingsTokens.Metric.inset)
        .padding(.top, SettingsTokens.Metric.inset)
        .padding(.bottom, Metric.bottomPadding)
    }

    private var chart: some View {
        let segments = segments
        let barWidth = min(Metric.maxBarWidth, plotWidth * Metric.barWidthRatio / CGFloat(max(1, days.count)))

        return Chart(segments.indices, id: \.self) { index in
            let bar = segments[index]
            BarMark(
                x: .value("Day", String(bar.day)),
                yStart: .value("Start", bar.start),
                yEnd: .value("Items", bar.end),
                width: .fixed(barWidth)
            )
            .foregroundStyle(bar.series.tone.color)
            .accessibilityLabel(Text(verbatim: Self.dayLabel(days[bar.day], now: now, calendar: calendar)))
            .accessibilityValue(Text("\(bar.series.name), \(bar.end - bar.start, format: .number.precision(.fractionLength(0)))"))
        }
        .chartXScale(domain: days.indices.map { String($0) })
        .chartYScale(domain: .automatic(includesZero: true))
        .chartPlotStyle { plot in
            plot.frame(height: Metric.plotHeight)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { plotWidth = $0 }
        }
        .chartXAxis {
            AxisMarks { value in
                if let day = value.as(String.self).flatMap(Int.init), days.indices.contains(day) {
                    AxisValueLabel {
                        Text(verbatim: Self.dayLabel(days[day], now: now, calendar: calendar))
                            .settingsFont(.chartAxis)
                            .foregroundStyle(SettingsTokens.secondaryText)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: SettingsTokens.Metric.tileEdgeWidth))
                    .foregroundStyle(SettingsTokens.hairline)
                AxisValueLabel {
                    if let count = value.as(Double.self) {
                        Text(count, format: .number)
                            .settingsFont(.chartTick)
                            .monospacedDigit()
                            .foregroundStyle(SettingsTokens.secondaryText)
                    }
                }
            }
        }
    }

    /// The day under a bar: the weekday and the day of the month, or Today for the day the window was counted to.
    static func dayLabel(_ day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Today") }
        let weekday = day.formatted(Date.FormatStyle(calendar: calendar).weekday(.abbreviated))
        return "\(weekday) \(calendar.component(.day, from: day))"
    }
}

/// Storage used by each kind, then the free space when the server could read it.
struct SettingsStorageBar: View {
    struct Part {
        let name: String
        let tone: SettingsTokens.Tone
        let bytes: Int64
    }

    let parts: [Part]
    /// Nil when the server could not read the free space, which leaves that segment and its legend entry out.
    var freeBytes: Int64?
    var freeName: String = String(localized: "Free")
    var label: LocalizedStringKey = "Storage Usage"
    private typealias Metric = SettingsTokens.Metric.Usage

    private var shares: [(bytes: Double, color: Color)] {
        let used = parts.filter { $0.bytes > 0 }.map { (Double($0.bytes), $0.tone.color) }
        guard let freeBytes, freeBytes > 0 else { return used }
        return used + [(Double(freeBytes), SettingsTokens.selection)]
    }

    private var legend: [UsageLegend.Entry] {
        let used = parts.map { UsageLegend.Entry(name: $0.name, value: size($0.bytes), tone: $0.tone) }
        guard let freeBytes else { return used }
        return used + [UsageLegend.Entry(name: freeName, value: size(freeBytes), tone: nil)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.storageLegendGap) {
            bar
            UsageLegend(entries: legend)
        }
        .padding(.horizontal, SettingsTokens.Metric.inset)
        .padding(.top, SettingsTokens.Metric.inset)
        .padding(.bottom, Metric.bottomPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
    }

    private var bar: some View {
        GeometryReader { geometry in
            let shares = shares
            let total = shares.reduce(0) { $0 + $1.bytes }
            let width = max(0, geometry.size.width - Metric.storageGap * CGFloat(max(0, shares.count - 1)))

            HStack(spacing: Metric.storageGap) {
                ForEach(shares.indices, id: \.self) { index in
                    // A new Marfa has nothing to divide.
                    let share = total > 0 ? width * shares[index].bytes / total : 0
                    Rectangle().fill(shares[index].color).frame(width: share)
                }
            }
        }
        .frame(height: Metric.storageHeight)
        .background(SettingsTokens.selection)
        .clipShape(.capsule)
        .accessibilityHidden(true)
    }

    private func size(_ bytes: Int64) -> String {
        max(0, bytes).formatted(.byteCount(style: .file))
    }
}

private struct UsageLegend: View {
    struct Entry {
        let name: String
        let value: String
        let tone: SettingsTokens.Tone?
    }

    let entries: [Entry]
    private typealias Metric = SettingsTokens.Metric.Usage

    var body: some View {
        TagFlowLayout(spacing: Metric.legendColumnGap, rowSpacing: Metric.legendRowGap) {
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                HStack(spacing: SettingsTokens.Metric.dotGap) {
                    swatch(entry.tone)
                    Text(verbatim: entry.name)
                    Text(verbatim: entry.value).foregroundStyle(SettingsTokens.secondaryText).monospacedDigit()
                }
                .settingsFont(.small)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func swatch(_ tone: SettingsTokens.Tone?) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metric.swatchRadius)
        return shape.fill(tone?.color ?? SettingsTokens.selection)
            .overlay {
                if tone == nil {
                    shape.strokeBorder(SettingsTokens.hairline, lineWidth: SettingsTokens.Metric.tileEdgeWidth)
                }
            }
            .frame(width: Metric.swatchSize, height: Metric.swatchSize)
            .accessibilityHidden(true)
    }
}

#Preview("Usage Chart") {
    let today = Calendar.current.startOfDay(for: .now)
    let days = (-6...0).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    SettingsCard {
        SettingsUsageChart(days: days, series: [
            .init(name: "Tasks", tone: .amber, values: [9, 14, 11, 16, 18, 5, 4]),
            .init(name: "Bookmarks", tone: .teal, values: [8, 12, 14, 16, 12, 8, 4]),
            .init(name: "Notes", tone: .blue, values: [4, 6, 5, 8, 7, 4, 1]),
        ])
    }
    .frame(width: SettingsTokens.Metric.column)
}

#Preview("Storage Usage") {
    SettingsCard {
        SettingsStorageBar(parts: [
            .init(name: "Files", tone: .green, bytes: 18_500_000_000),
            .init(name: "Versions", tone: .red, bytes: 3_200_000_000),
            .init(name: "Database", tone: .blue, bytes: 1_100_000_000),
        ], freeBytes: 35_600_000_000)
    }
    .frame(width: SettingsTokens.Metric.column)
}
