import SwiftUI

/// What Info says of an item that the item page cannot: where it came from and when, where it is (and a way to move it),
/// who else keeps it, and the versions before this one.
struct PanelInfoModel {
    let item: Item
    /// The name of the source that made the item.
    var source: String?
    var version: ItemVersion
    /// A PDF's page count, once read.
    var pages: Int?
    /// Which of Library and Feed the item may move to, or nil where it may not move at all.
    var moves: Set<Tier>?
    let move: (Tier) -> Void
    /// When the item leaves the Feed, where its type has a window and the item is active in the Feed.
    var leavesTheFeed: Date?
}

struct PanelInfoView<Legacy: View>: View {
    @CurrentLibrary private var library
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    let model: PanelInfoModel
    let onShowHistory: () -> Void
    @ViewBuilder let legacy: Legacy

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let line = PanelKeptBy.line(of: model.item, source: model.source, direction: direction) { keptBy(line) }
            PanelFacts(
                facts: PanelInfo.facts(of: model.item, source: model.source, version: model.version, pages: model.pages, format: dateFormat),
                trailing: [(name: String(localized: "In"), content: AnyView(placeControl))] + leavesTheFeed)
            historySection
            legacy
        }
        .task { await library.readConnectors() }
        .task(id: model.version) { PanelHistory.shared.ask(model.item.id, version: model.version, in: library) }
    }

    // MARK: Who keeps it

    /// How the connector that wrote the item moves items of its type, once the server has said.
    private var direction: ConnectorDirection? {
        guard let source = model.item.source else { return nil }
        return library.connectors?.direction(source: source, type: model.item.type)
    }

    /// Said once at the top, with the reason the item's allowances give.
    private func keptBy(_ line: PanelKeptLine) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: line.symbol).foregroundStyle(.tertiary).accessibilityHidden(true)
                Text(verbatim: line.text)
            }
            .interfaceFont(.callout)
            .foregroundStyle(.secondary)
            Divider()
        }
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: In

    /// The tier as a value with two small arrows, whose menu moves the item: one undo step, with a notice where the
    /// move is refused.
    @ViewBuilder private var placeControl: some View {
        let tier = model.item.tier
        let name = Self.name(of: tier)
        if let moves = model.moves {
            Menu {
                ForEach([Tier.library, .feed], id: \.self) { option in
                    Toggle(Self.name(of: option), isOn: Binding(get: { option == tier }, set: { _ in if option != tier { model.move(option) } }))
                        .disabled(option != tier && !moves.contains(option))
                }
            } label: {
                HStack(spacing: 5) {
                    Text(name)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("In")
            .accessibilityValue(name)
            .accessibilityIdentifier("PanelIn")
        } else {
            Text(name)
        }
    }

    /// The day the item leaves the Feed, beside In, as any value's day is written.
    private var leavesTheFeed: [(name: String, content: AnyView)] {
        guard let date = model.leavesTheFeed else { return [] }
        let day = DateDisplay.text(of: date, hasTime: false, place: .value, format: dateFormat)
        return [(name: String(localized: "Leaves the Feed"), content: AnyView(Text(verbatim: day)))]
    }

    private static func name(of tier: Tier) -> String {
        tier == .feed ? String(localized: "Feed") : String(localized: "Library")
    }

    // MARK: History

    /// The versions, newest first, starting with the one the item holds now. An item at version 1 has nothing earlier to
    /// ask for, so its list is that one row.
    @ViewBuilder private var historySection: some View {
        let version = Int(model.version.rawValue)
        let history = version > 1 ? PanelHistory.shared.model(of: model.item.id, version: model.version, in: library) : nil
        let entries = VersionThread.entries(
            snapshots: history?.snapshots ?? [], current: model.item, currentText: nil, in: library.catalogue)
        let isRead = version <= 1 || history?.phase == .loaded
        PanelHeading(title: String(localized: "History"), count: isRead ? entries.count : nil)
        ForEach(entries.prefix(PanelHistory.shown + 1)) { entry in
            PanelHistoryRow(entry: entry, currentName: currentName(version: version), format: dateFormat)
        }
        if let history {
            switch history.phase {
            case .idle, .loading:
                if entries.count == 1 { ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading) }
            case .failed:
                Text("History isn’t available right now.").interfaceFont(.callout).foregroundStyle(.secondary)
            case .loaded:
                EmptyView()
            }
        }
        if entries.count > PanelHistory.shown + 1 || history?.hasMore == true {
            PanelMoreButton(
                title: String(localized: "Show All \(entries.count) Versions"), identifier: "PanelShowAllVersions", action: onShowHistory)
        }
    }

    /// Who wrote the version the item holds: the source that made it, at version 1. Later, the server keeps no record of the
    /// writer until the version is replaced.
    private func currentName(version: Int) -> String {
        if version <= 1, let source = model.source { return source }
        return String(localized: "Current Version")
    }
}

/// One version: the symbol of who wrote it, their name, and when.
private struct PanelHistoryRow: View {
    @Environment(\.interfaceTextSize) private var textSize
    let entry: VersionEntry
    let currentName: String
    let format: DateFormat

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: 8) {
            Image(systemName: entry.isCurrent ? "clock" : PanelHistory.symbol(of: entry.writer))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(verbatim: entry.isCurrent ? currentName : (entry.writer?.displayName ?? String(localized: "Not known"))).lineLimit(1)
            Spacer(minLength: 6)
            if let written = entry.written {
                let text = VersionBlocks.when(written, format: format)
                Text(verbatim: entry.writtenIsApproximate ? String(localized: "About \(text)") : text)
                    .interfaceFont(.callout).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
            }
        }
        .interfaceFont(.body)
        .frame(maxWidth: .infinity, minHeight: PanelMetrics.rowHeight * scale, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
