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
    let history: PanelHistory
    let move: (Tier) -> Void
}

struct PanelInfoView<Legacy: View>: View {
    @CurrentLibrary private var library
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    let model: PanelInfoModel
    let onShowHistory: () -> Void
    @ViewBuilder let legacy: Legacy

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let line = PanelKeptBy.line(of: model.item, source: model.source) { keptBy(line) }
            PanelFacts(
                facts: PanelInfo.facts(of: model.item, source: model.source, version: model.version, pages: model.pages, format: dateFormat),
                trailing: (String(localized: "In"), AnyView(placeControl)))
            historySection
            legacy
        }
        .task(id: model.version) { model.history.ask(model.item.id, version: model.version, in: library) }
        .onDisappear { model.history.stop() }
    }

    // MARK: Who keeps it

    /// Said once at the top, with the reason the item's allowances give.
    private func keptBy(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock").foregroundStyle(.tertiary).accessibilityHidden(true)
                Text(verbatim: line)
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
                    Button { model.move(option) } label: {
                        if option == tier { Label(Self.name(of: option), systemImage: "checkmark") } else { Text(Self.name(of: option)) }
                    }
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

    private static func name(of tier: Tier) -> String {
        tier == .feed ? String(localized: "Feed") : String(localized: "Library")
    }

    // MARK: History

    @ViewBuilder private var historySection: some View {
        let version = Int(model.version.rawValue)
        if let history = model.history.model, version > 1 {
            let entries = VersionThread.entries(
                snapshots: history.snapshots, current: model.item, currentText: nil, in: library.catalogue)
            let earlier = Array(entries.dropFirst())
            PanelHeading(title: String(localized: "History"), count: history.phase == .loaded ? entries.count : nil)
            switch history.phase {
            case .idle, .loading:
                if earlier.isEmpty { ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading) }
            case .failed:
                Text("History isn’t available right now.").interfaceFont(.callout).foregroundStyle(.secondary)
            case .loaded:
                EmptyView()
            }
            ForEach(earlier.prefix(PanelHistory.shown)) { entry in
                PanelHistoryRow(entry: entry, format: dateFormat)
            }
            if earlier.count > PanelHistory.shown || history.hasMore {
                PanelMoreButton(
                    title: String(localized: "Show All \(entries.count) Versions"), identifier: "PanelShowAllVersions", action: onShowHistory)
            }
        } else if version <= 1 {
            PanelHeading(title: String(localized: "History"))
            Text("No earlier versions").interfaceFont(.callout).foregroundStyle(.tertiary)
        }
    }
}

/// One earlier version: the symbol of who wrote it, their name, and when.
private struct PanelHistoryRow: View {
    @Environment(\.interfaceTextSize) private var textSize
    let entry: VersionEntry
    let format: DateFormat

    var body: some View {
        let scale = InterfaceStyle.scale(for: textSize)
        HStack(spacing: 8) {
            Image(systemName: PanelHistory.symbol(of: entry.writer))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(verbatim: entry.writer?.displayName ?? String(localized: "Not known")).lineLimit(1)
            Spacer(minLength: 6)
            if let written = entry.written {
                let text = DateDisplay.text(of: written, place: .value, format: format)
                Text(verbatim: entry.writtenIsApproximate ? String(localized: "About \(text)") : text)
                    .interfaceFont(.callout).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
            }
        }
        .interfaceFont(.body)
        .frame(maxWidth: .infinity, minHeight: PanelMetrics.rowHeight * scale, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
