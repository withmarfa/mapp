import AppKit
import SwiftUI

/// The version chosen, read as a page: its type, title, the property rows the head would list, and its text, with what
/// it added since the version before it marked in green and what it dropped struck through.
struct VersionPageColumn: View {
    @CurrentLibrary private var library
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @AppStorage(PagePlacements.key) private var placements = PagePlacements()
    @AppStorage(InterfaceKey.textSize) private var interfaceTextSize = InterfaceStyle.defaultTextSize
    @StoredPageStyle private var style
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
        let content = entry.content
        let rows = content.rows(
            placement: placements.placement(of: content.type, in: library.catalogue), in: library.catalogue, format: dateFormat)
        let size = CGFloat(InterfaceStyle.defaultTextSize) * InterfaceStyle.scale(for: interfaceTextSize)
        let titleSize = style.titleSize
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageKicker(kicker: kicker(of: content.type)) {}
                    .padding(.bottom, size * 6 / 13)
                if let title = content.title, !title.isEmpty {
                    Text(verbatim: title)
                        .font(.system(size: titleSize, weight: .semibold)).tracking(titleSize * Typography.titleTracking)
                        .textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                } else if content.title != nil {
                    Text("Untitled").font(.system(size: titleSize, weight: .semibold)).tracking(titleSize * Typography.titleTracking)
                        .foregroundStyle(.tertiary)
                }
                if !rows.isEmpty { propertyRows(rows, size: size) }
                Group {
                    if let text = content.text {
                        VersionTextView(old: older?.content.text, new: text, size: CGFloat(style.textSize))
                    } else {
                        Text("No text").font(.system(size: CGFloat(style.textSize))).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, rows.isEmpty ? 24 : 20)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("VersionHistoryPage")
    }

    /// The type's mark and name over the title, as the head draws it, with no flags and nothing to change.
    private func kicker(of type: TypeID) -> PageHead.Kicker {
        let name = library.catalogue.itemTypes[type].map { PageHead.localized($0.label) } ?? library.catalogue.label(for: type)
        return PageHead.Kicker(typeName: name, typeIcon: library.catalogue.icon(for: type), changesType: false, flags: [])
    }

    /// The rows as the item's page draws them: a symbol and the name in a column of one width, the value beside it,
    /// over a hairline. Read only: a version is not edited here.
    private func propertyRows(_ rows: [VersionFactRow], size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    HStack(spacing: size * 8 / 13) {
                        Image(systemName: row.symbol ?? "text.alignleft")
                            .frame(width: size * 16 / 13)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(verbatim: row.label).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(width: size * 150 / 13, alignment: .leading)
                    Text(verbatim: row.value).lineLimit(2).textSelection(.enabled).help(row.value)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: size * 30 / 13)
                .accessibilityElement(children: .combine)
            }
        }
        .font(.system(size: size))
        .padding(.top, size * 16 / 13)
        .padding(.bottom, size * 8 / 13)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// A version's text, read against the text before it. The comparison runs off the main actor, since a long text
/// takes a moment, and the text shows as it was until it is done.
struct VersionTextView: View {
    let old: String?
    let new: String
    /// The page's text size, which the lines and the headings over them scale from.
    let size: CGFloat
    @State private var lines: [ReadLine]?

    private struct Job: Hashable {
        let old: String?
        let new: String
    }

    var body: some View {
        let shown = TextExcerpt(new)
        VStack(alignment: .leading, spacing: 6) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(lines ?? []) { VersionLineView(line: $0, size: size) }
            }
            .textSelection(.enabled)
            if shown.omitted > 0 {
                Text("\(shown.omitted.formatted()) more characters aren’t shown.")
                    .font(.system(size: size))
                    .foregroundStyle(.secondary)
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
    let size: CGFloat

    var body: some View {
        content.font(.system(size: size))
    }

    @ViewBuilder private var content: some View {
        switch line.kind {
        case .blank:
            Color.clear.frame(height: 6)
        case .rule:
            Divider()
        case .heading(let level):
            Text(attributed)
                .font(.system(size: Typography.pageSize(Typography.headingSize(level), at: size), weight: level <= 3 ? .bold : .semibold))
                .padding(.top, 6)
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
            Text(attributed).font(.system(size: size * Typography.codeBlockRatio, design: .monospaced))
        case .paragraph:
            Text(attributed)
        case .table(let table):
            VersionTableView(table: table)
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
            // A wiki link is tinted as the item page tints one, and is not followed either.
            if span.wikiLink { piece.foregroundColor = Color.accentColor }
            switch span.change {
            case .same: break
            case .added: piece.backgroundColor = VersionLooks.added
            case .removed:
                piece.strikethroughStyle = .single
                piece.foregroundColor = .secondary
            }
            result += piece
        }
        return result
    }
}

/// How Version History marks words a version added: green, since the accent marks what is chosen (`docs/look.md`).
enum VersionLooks {
    static let addedLightOpacity = 0.15
    static let addedDarkOpacity = 0.26

    static let added = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(srgbRed: 48 / 255, green: 164 / 255, blue: 108 / 255, alpha: isDark ? addedDarkOpacity : addedLightOpacity)
    })

    /// The board's third text level, for block headings and writers' names: ink at 36%, white at 36% in dark.
    static let faint = neutral(0.36)
    /// The wash behind Current: ink at 6%, white at 6% in dark.
    static let currentWash = neutral(0.06)

    private static func neutral(_ opacity: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(opacity)
        })
    }
}
