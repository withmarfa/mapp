import SwiftUI

/// What the Outline shows: facts worked out from the text or the file, then the headings the page or the file gives.
struct PanelOutlineModel {
    var headings: [OutlineHeading] = []
    /// Reading Time and Words, once counted. Nil for an item with no text and until the count is back.
    var text: PanelTextFacts?
    /// A PDF's pages and contents, once read. Nil for any other item.
    var pdf: PanelPDFFacts?
    var isPDF = false

    /// The part is offered only when the item has something for it: headings, or a PDF.
    var hasContent: Bool { !headings.isEmpty || isPDF }

    var facts: [PanelFact] {
        if isPDF { return pdf.map { [PanelFact(name: String(localized: "Pages"), value: $0.pages.formatted())] } ?? [] }
        guard let text else { return [] }
        return [
            PanelFact(name: String(localized: "Reading Time"), value: String(localized: "\(text.readingMinutes) min", comment: "Minutes to read.")),
            PanelFact(name: String(localized: "Words"), value: text.words.formatted()),
        ]
    }
}

struct PanelOutlineView: View {
    @Environment(\.interfaceTextSize) private var textSize
    let model: PanelOutlineModel
    /// Goes to a heading of the item's text, or to a page of the PDF.
    let onHeading: (Int) -> Void
    var onPage: (Int) -> Void = { _ in }

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        VStack(alignment: .leading, spacing: 0) {
            PanelFacts(facts: model.facts)
            if model.isPDF {
                if let rows = model.pdf?.contents, !rows.isEmpty {
                    PanelHeading(title: String(localized: "Contents"), count: rows.count)
                    outline(rows.map { row in (id: row.index, level: row.level, title: row.title, go: { onPage(row.page) }) }, scale: scale)
                } else if model.pdf != nil {
                    Text("This PDF has no contents.")
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                        .accessibilityIdentifier("OutlineNoContents")
                }
            } else if !model.headings.isEmpty {
                PanelHeading(title: String(localized: "Headings"), count: model.headings.count)
                outline(model.headings.map { heading in
                    (id: heading.index, level: heading.level, title: heading.text, go: { onHeading(heading.index) })
                }, scale: scale)
            }
        }
    }

    /// Each heading is 26 high, indented by its level, with a hairline at its leading edge. The page does not report
    /// which heading is in view, so none is drawn dark.
    private func outline(_ rows: [(id: Int, level: Int, title: String, go: () -> Void)], scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.id) { row in
                Button(action: row.go) {
                    Text(verbatim: row.title)
                        .interfaceFont(row.level >= 3 ? .caption : .callout)
                        .foregroundStyle(row.level == 1 ? Color.primary.opacity(0.74) : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 12 * CGFloat(min(row.level, 3)))
                        .frame(maxWidth: .infinity, minHeight: PanelMetrics.outlineRowHeight * scale, alignment: .leading)
                        .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: 1.5) }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("OutlineHeading.\(row.id)")
            }
        }
    }
}

/// The facts of a part: a small grid of labels over values, two to a row, with no boxes. `trailing` holds the last facts,
/// given as views, such as the control In.
struct PanelFacts: View {
    let facts: [PanelFact]
    var trailing: [(name: String, content: AnyView)] = []

    var body: some View {
        let count = facts.count + trailing.count
        Grid(alignment: .topLeading, horizontalSpacing: PanelMetrics.factsGap.width, verticalSpacing: PanelMetrics.factsGap.height) {
            ForEach(Array(stride(from: 0, to: count, by: 2)), id: \.self) { start in
                GridRow {
                    cell(start)
                    if start + 1 < count { cell(start + 1) } else { Color.clear.frame(height: 0) }
                }
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder private func cell(_ index: Int) -> some View {
        if index < facts.count {
            PanelFactCell(fact: facts[index])
        } else {
            let fact = trailing[index - facts.count]
            PanelFactCell(name: fact.name) { fact.content }
        }
    }
}

struct PanelFactCell<Value: View>: View {
    let name: String
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.factLabelGap) {
            Text(verbatim: name).interfaceFont(.callout).foregroundStyle(.secondary).lineLimit(1)
            value.interfaceFont(.body).lineLimit(1).minimumScaleFactor(0.8).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gridColumnAlignment(.leading)
    }
}

extension PanelFactCell where Value == Text {
    init(fact: PanelFact) { self.init(name: fact.name) { Text(verbatim: fact.value) } }
}
