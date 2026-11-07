import SwiftUI

/// The version chosen, read as a page: its title, the properties its type pins, and its text, with what it added
/// since the version before it marked and what it dropped struck through.
struct VersionPageColumn: View {
    @CurrentLibrary private var library
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()
    @Environment(\.interfaceTextSize) private var textSize
    let mode: VersionHistoryMode
    let list: VersionList?

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Why Restore Version is dimmed, read on each change of the library, so an item changed or deleted
                // elsewhere is judged as it stands now.
                if let reason = VersionHistoryMode.reason(for: mode.restoreCheck(in: library)) {
                    Text(reason)
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                        .accessibilityIdentifier("VersionHistoryReason")
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch mode.thread.phase {
        case .idle, .loading:
            ProgressView("Loading versions…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let failure):
            ContentUnavailableView {
                Label("No Versions to Show", systemImage: "clock.arrow.circlepath")
            } description: {
                Text(isDeleted ? String(localized: "This item is in Recently Deleted, where its history can’t be read. Recover it to see its versions.") : failure.message)
            } actions: {
                if failure != .unsupported { Button("Try Again") { mode.thread.load() } }
            }
        case .loaded:
            if let list, let entry = list.entry(mode.thread.selection) {
                page(of: entry, older: list.older(than: entry))
            } else {
                ContentUnavailableView("Choose a Version", systemImage: "text.alignleft",
                    description: Text("Pick one on the left to read it."))
            }
        }
    }

    private var isDeleted: Bool { library.item(mode.item)?.state == .trashed }

    private func page(of entry: VersionEntry, older: VersionEntry?) -> some View {
        let pins = entry.content.pins(
            saved: entry.written, placement: placements.placement(of: entry.content.type, in: library.catalogue),
            in: library.catalogue, format: dateFormat)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let title = entry.content.title, !title.isEmpty {
                    Text(verbatim: title).interfaceFont(.largeTitle.bold()).textSelection(.enabled)
                } else if entry.content.title != nil {
                    Text("Untitled").interfaceFont(.largeTitle.bold()).foregroundStyle(.tertiary)
                }
                if !pins.isEmpty { pinRow(pins, of: entry.content.type) }
                if let text = entry.content.text {
                    VersionTextView(old: older?.content.text, new: text)
                } else {
                    Text("No text").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("VersionHistoryPage")
    }

    /// The pins as the item's page draws them: each key above its value, in a slot of the same width.
    private func pinRow(_ pins: [VersionFactRow], of type: TypeID) -> some View {
        let scale = InterfaceStyle.scale(for: textSize)
        return TagFlowLayout(spacing: 14 * scale) {
            ForEach(pins) { pin in
                VStack(alignment: .leading, spacing: 5 * scale) {
                    HStack(spacing: 4 * scale) {
                        if let symbol = pin.symbol {
                            Image(systemName: symbol).font(.system(size: 11 * scale)).accessibilityHidden(true)
                        }
                        Text(LocalizedStringKey(pin.label)).font(.system(size: 12 * scale))
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    if pin.id == PagePlacement.type {
                        PageChip(text: pin.value, kind: .type(icon: library.catalogue.icon(for: type)))
                    } else {
                        Text(verbatim: pin.value)
                            .interfaceFont(.body)
                            .lineLimit(1)
                            .frame(minHeight: 22 * scale)
                    }
                }
                .frame(width: 136 * scale, alignment: .leading)
                .help(pin.value)
            }
        }
    }
}

/// A version's text, read against the text before it. The comparison runs off the main actor, since a long text
/// takes a moment, and the text shows as it was until it is done.
struct VersionTextView: View {
    let old: String?
    let new: String
    @State private var lines: [ReadLine]?

    private struct Job: Hashable {
        let old: String?
        let new: String
    }

    var body: some View {
        let shown = TextExcerpt(new)
        VStack(alignment: .leading, spacing: 6) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(lines ?? []) { VersionLineView(line: $0) }
            }
            .textSelection(.enabled)
            if shown.omitted > 0 {
                Text("\(shown.omitted.formatted()) more characters aren’t shown.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: Job(old: old, new: new)) {
            let new = TextExcerpt(new).text
            let old = old.map { TextExcerpt($0).text }
            lines = await Task.detached(priority: .userInitiated) {
                ReadableText.lines(old.map { WordDiff.pieces(from: $0, to: new) } ?? [DiffPiece(text: new, change: .same)])
            }.value
        }
    }
}

private struct VersionLineView: View {
    let line: ReadLine

    var body: some View {
        switch line.kind {
        case .blank:
            Color.clear.frame(height: 6)
        case .rule:
            Divider()
        case .heading(let level):
            Text(attributed).font(Self.font(forHeading: level)).padding(.top, 6)
        case .bullet(let depth, let number):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number.map { "\($0)." } ?? "•").foregroundStyle(.secondary)
                Text(attributed)
            }
            .padding(.leading, CGFloat(depth) * 20)
        case .quote:
            Text(attributed).foregroundStyle(.secondary)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 3) }
        case .code:
            Text(attributed).font(.system(.body, design: .monospaced))
        case .paragraph:
            Text(attributed)
        case .table(let table):
            VersionTableView(table: table)
        }
    }

    private static func font(forHeading level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
    }

    private var attributed: AttributedString { line.spans.attributed }
}

/// A table of a version's text: a header row on a tint, rules between the rows and the columns, and cells that wrap.
private struct VersionTableView: View {
    let table: ReadTable

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            row(table.header, isHeader: true)
            ForEach(table.rows.indices, id: \.self) { index in
                Divider()
                row(table.rows[index], isHeader: false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator) }
        .padding(.vertical, 4)
    }

    private func row(_ cells: [[ReadSpan]], isHeader: Bool) -> some View {
        GridRow {
            ForEach(cells.indices, id: \.self) { column in
                Text(cells[column].attributed)
                    .fontWeight(isHeader ? .semibold : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(Self.alignment(of: table.alignments[column]))
                    .frame(maxWidth: .infinity, alignment: Self.frame(of: table.alignments[column]))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isHeader ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                    .overlay(alignment: .leading) {
                        if column > 0 { Rectangle().fill(.separator).frame(width: 1) }
                    }
            }
        }
    }

    private static func alignment(of alignment: ReadTable.Alignment) -> TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private static func frame(of alignment: ReadTable.Alignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

private extension [ReadSpan] {
    /// The spans as one text: how inline markdown sets them, and what the version added or dropped marked.
    var attributed: AttributedString {
        var result = AttributedString()
        for span in self {
            var piece = AttributedString(span.text)
            var intent: InlinePresentationIntent = []
            if span.bold { intent.insert(.stronglyEmphasized) }
            if span.italic { intent.insert(.emphasized) }
            if span.code { intent.insert(.code) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            // A link is marked, not made live: a version is read here, and its addresses are not followed from it.
            if span.link != nil { piece.underlineStyle = .single }
            // A wiki link is tinted as the note page tints one, and is not followed either.
            if span.wikiLink { piece.foregroundColor = Color.accentColor }
            switch span.change {
            case .same: break
            case .added: piece.backgroundColor = Color.accentColor.opacity(0.22)
            case .removed:
                piece.strikethroughStyle = .single
                piece.foregroundColor = .secondary
            }
            result += piece
        }
        return result
    }
}
